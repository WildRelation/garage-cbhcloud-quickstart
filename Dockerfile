FROM dxflrs/garage:v2.1.0 AS garage

FROM alpine:3.19
# gettext tillhandahåller envsubst för att ersätta env-variabler i garage.toml
RUN apk add --no-cache gettext
COPY --from=garage /garage /usr/local/bin/garage
COPY garage.toml /etc/garage.toml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 3900 3901 3902 3903
ENTRYPOINT ["/entrypoint.sh"]
CMD ["server"]
