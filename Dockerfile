# Commands to build and run nginx
# docker build -t <image name> nginx
# docker run -p 2080:2080 <image name>

# Build openssl image to fix nginx init issue
FROM nginx:latest as openssl_fixnginx_image
ENV DEBIAN_FRONTEND noninteractive

# deb-src address to download openssl package source
RUN sed -i 's/^deb \([^ ]* [a-z]* main\)$/&\ndeb-src \1/' /etc/apt/sources.list

RUN apt update && apt install -y apt-utils build-essential devscripts lintian && \
        apt build-dep -y openssl && apt source openssl

COPY openssl.fixnginxinit.patch /root/
# The following two env variables are used by dch to add a valid name and email address to the changelog
ENV DEBEMAIL info@us.ibm.com
ENV DEBFULLNAME IBM
RUN patch openssl-*/crypto/init.c /root/openssl.fixnginxinit.patch; cd openssl-*/; \
        dch -v $(apt info libssl1.1 | sed -n -e 's/^Version:\s*\(.*$\)/\1+grep11/p') 'patch for nginx use' \
        && debuild -b -uc -us \
        && cd /; tar -czf openssl_fixnginx.tgz libssl1.1_*_*.deb openssl_*_*.deb

FROM nginx:latest
ENV DEBIAN_FRONTEND noninteractive

# Fix openssl-fixnginx issue and install grep11 Debian package
COPY --from=openssl_fixnginx_image /openssl_fixnginx.tgz /
COPY *.deb /tmp/

# Need 'openssl' command to generate temporary key for nginx test
RUN tar -xzf openssl_fixnginx.tgz; rm openssl_fixnginx.tgz; apt update; apt -y install ./libssl1.1_*_*.deb ./openssl_*_*.deb /tmp/*$(uname -m | sed -e 's/x86_64/amd64/').deb; \
        rm -rf /var/lib/apt/lists/* /tmp/*.deb ./libssl1.1_*_*.deb ./openssl_*_*.deb

RUN ldconfig

# Update openssl engine configure
COPY openssl.cnf /etc/ssl/openssl.cnf

# Add nginx configure file, add 2080 port for test; add new html welcome file
COPY ssleng.index.html /usr/share/nginx/html

#nginx needs to explicitly setup which environment variables are allowed
COPY nginx-env.txt /tmp/nginx.conf
RUN cat /etc/nginx/nginx.conf >> /tmp/nginx.conf && mv /tmp/nginx.conf /etc/nginx/nginx.conf
COPY *.conf /etc/nginx/conf.d/

# start.sh create new certificate in cert folder and key when running docker run
RUN  mkdir -p /etc/nginx/cert
COPY start.sh /usr/sbin/
RUN chmod +x /usr/sbin/start.sh

# nginx testing port: 80 for http, 2080 for https (via openssl engine)
EXPOSE 2080/tcp 80/tcp

CMD ["start.sh"]
