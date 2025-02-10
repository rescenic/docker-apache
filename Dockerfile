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

# Install apache, php, certbot (Let's Encrypt client), and mod_ssl
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
# Ensure apache can bind to 80 and 443 as non-root
        libcap2-bin \
        certbot \
        python3-certbot-apache && \
    setcap 'cap_net_bind_service=+ep' /usr/sbin/apache2 && \
    dpkg --purge libcap2-bin && \
    apt-get -y autoremove && \
# As apache is never run as root, change dir ownership
    a2disconf other-vhosts-access-log && \
    chown -Rh www-data:www-data /var/run/apache2 && \
# Enable Apache modules
    a2enmod rewrite headers expires ext_filter ssl && \
# Install ImageMagick CLI tools
    apt-get -y install --no-install-recommends imagemagick && \
# Clean up apt setup files
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Override default apache and php config
COPY src/000-default.conf /etc/apache2/sites-available
COPY src/000-default-ssl.conf /etc/apache2/sites-available
COPY src/mpm_prefork.conf /etc/apache2/mods-available
COPY src/status.conf      /etc/apache2/mods-available
COPY src/99-local.ini     /etc/php/8.1/apache2/conf.d

# Enable SSL site
RUN a2ensite default-ssl

# Expose details about this docker image
COPY src/index.php /var/www/html
RUN rm -f /var/www/html/index.html && \
    mkdir /var/www/html/.config && \
    tar cf /var/www/html/.config/etc-apache2.tar etc/apache2 && \
    tar cf /var/www/html/.config/etc-php.tar     etc/php && \
    dpkg -l > /var/www/html/.config/dpkg-l.txt

# Expose HTTP and HTTPS ports
EXPOSE 80 443

USER www-data

ENTRYPOINT ["apache2ctl", "-D", "FOREGROUND"]
