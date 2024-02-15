FROM haproxy:lts-bullseye

LABEL maintainer="datvodev@outlook.com"
RUN mkdir --parents /var/lib/haproxy && chown -R haproxy:haproxy /var/lib/haproxy
RUN mkdir /run/haproxy
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

EXPOSE 26000
EXPOSE 8080
EXPOSE 8081