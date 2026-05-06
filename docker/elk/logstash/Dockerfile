FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LS_VER=9.2.3

# 1. Include dist files
COPY dist/ /root/dist/

# 2. Install dependencies
RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y \
        adduser \
        aria2 \
        bash \
        bzip2 \
        curl && \
# 3. Determine Arch & Install Logstash
    ARCH=$(arch) && \
    if [ "$ARCH" = "x86_64" ]; then LS_ARCH="amd64"; fi && \
    if [ "$ARCH" = "aarch64" ]; then LS_ARCH="arm64"; fi && \
    echo "Building for architecture: $ARCH" && \
    mkdir -p /etc/listbot && \
    cd /root/dist/ && \
    aria2c -s 16 -x 16 https://artifacts.elastic.co/downloads/logstash/logstash-$LS_VER-$LS_ARCH.deb && \
    dpkg -i logstash-$LS_VER-$LS_ARCH.deb && \
# 4. Copy Configs & Scripts
    cp entrypoint.sh /usr/bin/ && \
    chmod u+x /usr/bin/entrypoint.sh && \
    mkdir -p /usr/share/logstash/config && \
    cp logstash.conf /etc/logstash/ && \
    cp http_input.conf /etc/logstash/ && \
    cp http_output.conf /etc/logstash/ && \
    cp pipelines.yml /usr/share/logstash/config/pipelines.yml && \
    cp pipelines_sensor.yml /usr/share/logstash/config/pipelines_sensor.yml && \
    cp tpot-template.json /etc/logstash/ && \
# 5. Install Plugins
    cd /usr/share/logstash && \
    bin/logstash-plugin update logstash-filter-translate && \
    bin/logstash-plugin install logstash-output-syslog && \
# 6. Cleanup Configs (Standard T-Pot practice)
    rm /etc/logstash/pipelines.yml && \
    rm /etc/logstash/logstash.yml && \
# 7. Setup Permissions
    groupmod -g 2000 logstash && \
    usermod -u 2000 logstash && \
    chown -R logstash:logstash /etc/listbot \
                               /var/log/logstash/ \
                               /var/lib/logstash \
                               /usr/share/logstash/data \
                               /usr/share/logstash/config/pipelines* && \
    chmod 755 /usr/bin/entrypoint.sh && \
# 8. Final Cleanup
    apt-get autoremove -y --purge && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* \
           /tmp/* /var/tmp/* \
           /root/.cache \
           /root/*

# 9. Healthcheck
HEALTHCHECK --retries=10 CMD curl -s -XGET 'http://127.0.0.1:9600'

# 10. Run as non-root
USER logstash:logstash

# 11. Entry Point
CMD ["entrypoint.sh"]