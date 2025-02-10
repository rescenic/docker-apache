FROM ubuntu:noble

LABEL \
    maintainer="Muhammad Ridwan Hakim, S.T., CPITA, ITPMCP <adminrescen@gmail.com>" \
    original-author="Raja Subramanian" \
    description="A comprehensive Docker image to run Apache-2.4 PHP-8.3 applications like WordPress, Laravel, etc. with Let's Encrypt support" \
    version="1.0" \
    license="MIT" \
    repository="https://github.com/rescenic/docker-apache"

# Stop dpkg-reconfigure tzdata from prompting for input
ENV DEBIAN_FRONTEND=noninteractive

# Define environment variables (overridable at runtime)
ENV SERVER_DOMAIN=example.com
ENV ADMIN_EMAIL=admin@${SERVER_DOMAIN}

# Install Apache, PHP, Certbot (Let's Encrypt client), and dependencies
RUN apt-get update && \
    apt-get -y install \
        apache2 \
        libapache2-mod-php \
        libapache2-mod-auth-openidc \
        php-bcmath \
        php-cli \
        php-curl \
        php-gd \
        php-intl \
        php-json \
        php-ldap \
        php-mbstring \
        php-memcached \
        php-mysql \
        php-pgsql \
        php-soap \
        php-tidy \
        php-uploadprogress \
        php-xml \
        php-xmlrpc \
        php-yaml \
        php-zip \
        libcap2-bin \
        certbot \
        python3-certbot-apache && \
    setcap 'cap_net_bind_service=+ep' /usr/sbin/apache2 && \
    dpkg --purge libcap2-bin && \
    apt-get -y autoremove && \
    a2disconf other-vhosts-access-log && \
    chown -Rh www-data:www-data /var/run/apache2 && \
    a2enmod rewrite headers expires ext_filter ssl && \
    apt-get -y install --no-install-recommends imagemagick && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create self-signed SSL certificate
RUN mkdir -p /etc/letsencrypt/live/${SERVER_DOMAIN} && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/letsencrypt/live/${SERVER_DOMAIN}/privkey.pem \
        -out /etc/letsencrypt/live/${SERVER_DOMAIN}/fullchain.pem \
        -subj "/CN=${SERVER_DOMAIN}/O=Self-Signed Certificate"

# Copy Apache configuration files
COPY src/000-default.conf /etc/apache2/sites-available/
COPY src/000-default-ssl.template.conf /etc/apache2/sites-available/

# Replace domain placeholders in SSL config
RUN sed -i "s/__DOMAIN__/${SERVER_DOMAIN}/g" /etc/apache2/sites-available/000-default-ssl.template.conf && \
    sed -i "s/__EMAIL__/${ADMIN_EMAIL}/g" /etc/apache2/sites-available/000-default-ssl.template.conf && \
    mv /etc/apache2/sites-available/000-default-ssl.template.conf /etc/apache2/sites-available/000-default-ssl.conf && \
    a2ensite 000-default-ssl

# Expose details about this Docker image
COPY src/index.php /var/www/html
RUN rm -f /var/www/html/index.html && \
    mkdir /var/www/html/.config && \
    tar cf /var/www/html/.config/etc-apache2.tar etc/apache2 && \
    tar cf /var/www/html/.config/etc-php.tar etc/php && \
    dpkg -l > /var/www/html/.config/dpkg-l.txt

# Expose HTTP and HTTPS ports
EXPOSE 80 443

RUN chown -R www-data:www-data /var/log/apache2 && \
    ln -sf /dev/stdout /var/log/apache2/access.log && \
    ln -sf /dev/stderr /var/log/apache2/error.log

ENTRYPOINT ["apache2ctl", "-D", "FOREGROUND"]
