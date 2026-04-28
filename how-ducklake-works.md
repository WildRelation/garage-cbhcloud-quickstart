# How DuckLake Works

DuckLake is not a database by itself. It is a system that coordinates two separate services to behave like one:

- **PostgreSQL** — keeps track of what exists (the catalog)
- **Garage** — stores the actual data (the files)
- **DuckDB** — talks to both and makes it feel like a normal database

---

## The library analogy

Imagine a library:

```
PostgreSQL  =  the card catalog
               (index of all books, where they are, what they contain)

Garage      =  the shelves
               (where the actual books are physically stored)

DuckDB      =  the librarian
               (knows how to use the catalog to find and retrieve books)
```

When you ask "give me all users named Alice", DuckDB:
1. Asks PostgreSQL: "where is the users table stored?"
2. PostgreSQL answers: "in the file `s3://ducklake/users-abc123.parquet`"
3. DuckDB reads that file from Garage and returns the result

---

## What PostgreSQL actually stores

DuckLake creates its own internal tables inside PostgreSQL. You never touch these directly — DuckDB manages them automatically.

They look something like this:

```
ducklake_table
┌─────────────┬────────────────────────────────────────┐
│ table_name  │ created_at                             │
├─────────────┼────────────────────────────────────────┤
│ users       │ 2026-04-29                             │
│ orders      │ 2026-04-29                             │
└─────────────┴────────────────────────────────────────┘

ducklake_column
┌─────────────┬─────────────┬──────────┐
│ table_name  │ column_name │ type     │
├─────────────┼─────────────┼──────────┤
│ users       │ id          │ INTEGER  │
│ users       │ name        │ VARCHAR  │
└─────────────┴─────────────┴──────────┘

ducklake_data_file
┌─────────────┬───────────────────────────────────────────┐
│ table_name  │ file_path                                 │
├─────────────┼───────────────────────────────────────────┤
│ users       │ s3://ducklake/users-abc123.parquet        │
│ users       │ s3://ducklake/users-def456.parquet        │
└─────────────┴───────────────────────────────────────────┘
```

PostgreSQL always knows exactly which files in Garage belong to which table.

---

## What Garage actually stores

Garage stores parquet files — nothing more. It has no idea what "tables" or "columns" are. From Garage's perspective it just holds files:

```
s3://ducklake/
├── users-abc123.parquet
├── users-def456.parquet
└── orders-ghi789.parquet
```

---

## What happens step by step

### CREATE TABLE

```python
con.execute("CREATE TABLE users (id INT, name VARCHAR)")
```

```
DuckDB → PostgreSQL: "add a record: table 'users' with columns id and name"
DuckDB → Garage:     nothing yet, no data to store
```

### INSERT

```python
con.execute("INSERT INTO users VALUES (1, 'Alice')")
```

```
DuckDB → Garage:     write file  s3://ducklake/users-abc123.parquet
DuckDB → PostgreSQL: "users now has a file at s3://ducklake/users-abc123.parquet"
```

### SELECT

```python
con.execute("SELECT * FROM users").fetchall()
```

```
DuckDB → PostgreSQL: "which files belong to users?"
PostgreSQL → DuckDB: "s3://ducklake/users-abc123.parquet"
DuckDB → Garage:     read that file
DuckDB → you:        returns the rows
```

### UPDATE

```python
con.execute("UPDATE users SET name = 'Bob' WHERE id = 1")
```

Parquet files are immutable — they cannot be edited. So DuckLake:

```
DuckDB → Garage:     write a NEW file  s3://ducklake/users-def456.parquet
                     (with the updated data)
DuckDB → PostgreSQL: "users-abc123.parquet is old, users-def456.parquet is current"
```

The old file stays in Garage until you run `VACUUM`.

### DELETE

```python
con.execute("DELETE FROM users WHERE id = 1")
```

Same as UPDATE — DuckLake writes a new parquet file without that row and marks
the old one as outdated in PostgreSQL.

### DROP TABLE

```python
con.execute("DROP TABLE users")
```

```
DuckDB → PostgreSQL: remove all records for table 'users'
DuckDB → Garage:     nothing (files stay until VACUUM)
```

---

## Why the catalog must be in PostgreSQL

Without PostgreSQL, nobody knows:

- What tables exist
- What columns they have
- Which files in Garage belong to which table
- Which version of a file is current

The files in Garage are just blobs with opaque names like `users-abc123.parquet`.
Without the catalog you cannot reconstruct which file is which.

---

## Why any PostgreSQL works

DuckLake connects to PostgreSQL using the standard PostgreSQL protocol — the same
protocol used by every PostgreSQL client in the world. It does not care about the
hosting platform. It only needs:

- A host that is reachable from the internet
- A valid database name, username, and password

This means you can use:

```python
# cbhcloud
'ducklake:postgres:host=<pg-deployment>.app.cloud.cbh.kth.se dbname=mydb user=myuser password=mypassword port=5432'

# Neon
'ducklake:postgres:host=ep-xxx.us-east-1.aws.neon.tech dbname=mydb user=myuser password=mypassword port=5432'

# Local
'ducklake:postgres:host=localhost dbname=mydb user=myuser password=mypassword port=5432'
```

DuckLake does not know or care where PostgreSQL is running.

---

## The ATTACH statement explained

```python
con.execute("""
ATTACH 'ducklake:postgres:host=<host> dbname=<db> user=<user> password=<password> port=5432'
AS my_lake (DATA_PATH 's3://ducklake/');
""")
```

Breaking it down:

```
ATTACH                → tell DuckDB to connect to an external data source

'ducklake:postgres:…' → use the DuckLake extension with a PostgreSQL catalog
                        (this is where the catalog lives)

AS my_lake            → give this lake a name to reference it in queries

DATA_PATH 's3://ducklake/'
                      → this is where DuckDB will read and write parquet files
                        (this points to your Garage bucket)
```

After this, `USE my_lake` tells DuckDB to use this lake by default so you
don't have to prefix every query.

---

## Full picture

```
your code
    │
    ▼
 DuckDB
    ├──── PostgreSQL  (what exists and where)
    └──── Garage/S3   (the actual data files)
```

DuckDB is the only component that talks to both. PostgreSQL and Garage never
communicate with each other directly.
