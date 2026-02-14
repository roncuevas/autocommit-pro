FROM alpine:3.21

RUN apk add --no-cache bash git tzdata

WORKDIR /app

COPY autocommit.sh config.sh.example entrypoint.sh ./

RUN chmod +x entrypoint.sh

ENTRYPOINT ["bash", "entrypoint.sh"]
