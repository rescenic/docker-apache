# Description

DIY AWS Lambda for PHP applications!

Docker image containing Ubuntu 24.04 LTS core with Apache 2.4 and PHP 8.3 with Self Signed Certificate & Let's Encrypt Support (Optional). This image is designed to be used in AWS environments for high-density PHP application hosting. WordPress 5.x and Drupal 10.x and later are tested to work.

# Architecture Overview

- Run multiple EC2 instances across different availability zones to create a redundant Docker Swarm.
- CloudWatch alarms must be used to restart failed EC2 instances.
- All EC2 instances must join the Docker Swarm and mount a common EFS volume on `/srv`.
- Docker container will mount `/srv/example.com/www` as the Apache `DocumentRoot` to serve PHP applications.
- RDS must be used for hosting databases.
- When this image is run as a Docker service in the swarm, a unique port on the host (e.g., TCP:8001) is mapped to 80 within the container.
- AWS Target Group `example-com` is created with all the EC2 instances of the swarm and a specific TCP port (e.g., TCP:8001) and attached to ALB.
- Docker mesh routing is not cookie/sticky session aware and disabled. HTTP load balancing is fully managed on AWS ALB.
- AWS ALB rules are used to route example.com and www.example.com requests to `example-com` Target Group.
- AWS ALB is also used for HTTPS termination, while Docker containers provide only vanilla HTTP.
- Outbound emails must be routed via SES (Drupal SMTP module, WP SMTP plugin, etc.).
- Apache logs are sent to stdout/stderr and can be routed to AWS CloudWatch using the Docker `awslogs` log driver.

# Filesystem Layout

- `/srv` -- base directory to be published via AWS EFS to all nodes, subdirectories `/srv/example.com`, `/srv/example.net`, etc., to be created for each website/domain.
- `/srv/example.com/www` -- root folder for PHP applications (WordPress root, Drupal root, etc.), mounted within Docker containers as Apache `DocumentRoot`.
- `/srv/example.com/etc/apache` and `/srv/example.com/etc/php` -- optional Apache/PHP config.
- `/srv/example.com/mysqlbackup` -- used for storing MySQL dumps.

# Small But Significant Things

- Apache MPM prefork is configured to reduce RAM usage, and a WordPress 5.x container will idle around 50-75MB of RAM.
- WordPress W3TC plugin cache folder is in `$WP_ROOT/wp-content/cache`. EFS is slow, so it's recommended to move the cache folder inside the Docker container. Delete the cache folder and run `ln -s /srv/example.com/www/wp-content/cache /tmp`. This will improve cache performance.
- PHP `post_max_size` and `upload_max_filesize` are increased to 1G and 512M to handle large file uploads.
- EFS is slow, so PHP opcache revalidation time is increased from the default 2 seconds to 300 seconds.
- Apache processes run as `www-data`. Inside the Docker instance, none of the processes are run as `root`. `setcap` is used to permit the non-root Apache process to bind to TCP port 80.
- Apache config is aware of SSL termination on AWS ALB or CloudFlare Flexible SSL settings. WordPress site URL can be set to `https://www.example.com`, and SSL termination can be done on AWS ALB or CloudFlare without causing infinite HTTP redirection errors.
- To view the default Apache and PHP config, run the Docker image without mapping an external `DocumentRoot` and access the container via `http://localhost:8001/index.php` (returns `phpinfo`) and `http://localhost:8001/.config` (contains `/etc/apache` and `/etc/php` tar files). This can be used for further customization.
- To use custom Apache config, extract the base Apache config in `/srv/example.com/etc` and then bind-mount it inside the container. Example: `docker run -v /srv/example.com/etc/php:/etc/php:ro -v /srv/example.com/etc/apache:/etc/apache:ro ...`
- WordPress updates can be handled outside the Docker environment via WP-CLI. From an independent EC2 instance: 1) Install all Apache/PHP WordPress dependencies, 2) Mount the EFS `/srv` volume, 3) Run `cd /srv/example.com/www && wp-cli plugin update --all`.

# Building

To build:

```bash
docker build --no-cache -t rescenic/php-apache-ubuntu:noble .
```

# Running

## Example 1: Basic Usage

Run with an internal document root to reveal Apache/PHP config. See `http://localhost/index.php` and `http://localhost/.config/`.

```bash
docker run --name=test -p 80:80 rescenic/php-apache-ubuntu:noble
```

## Example 2: Testing WordPress

Run a WordPress site from `/srv/example.com/www`.

```bash
docker run --name=example-com -v /srv/example.com/www:/var/www/html -p 80:80 rescenic/php-apache-ubuntu:noble
```

## Example 3: Using Custom Apache2 and PHP Config

Run a WordPress site from `/srv/example.com/www`, but this time use custom Apache and PHP config from `/srv/example.com/etc/{apache,php}`.

```bash
docker run --name=example-com -v /srv/example.com/www:/var/www/html -v /srv/example.com/etc/apache2:/etc/apache2:ro -v /srv/example.com/etc/php:/etc/php:ro -p 80:80 rescenic/php-apache-ubuntu:noble
```

## Example 4: Running as a Docker Service in a Docker Swarm

Run 2 replicas of the container as a Docker service. This command must be run from a Docker Swarm manager node. AWS ALB and Target Group must be created to route traffic for `example.com` to this container:

```bash
docker service create --replicas 2 --name example-com --publish published=8000,target=80,mode=host --mount type=bind,source=/srv/example.com/www,destination=/var/www/html rescenic/php-apache-ubuntu:noble
```

## Example 5: Running Let's Encrypt

To manually obtain an SSL certificate using Certbot, follow these steps:

```bash
docker exec -it example-com certbot certonly --webroot -w /var/www/html -d example.com -d www.example.com
```

Then, update the Apache SSL config (`000-default-ssl.conf`) and restart Apache:

```bash
service apache2 restart
```

That command is missing from the README.md. Would you like me to add it under the **Running** section as an **Example 6: Running with environment variables**?

Something like this:

---

## Example 6: Running with environment variables

Run the container with environment variables for **SERVER_DOMAIN** and **ADMIN_EMAIL**, which are used for configuration inside the container:

```bash
docker run --name=my_php_app \
    -p 80:80 -p 443:443 \
    -e SERVER_DOMAIN=example.com \
    -e ADMIN_EMAIL=admin@example.com \
    rescenic/php-apache-ubuntu:noble
```

This will:

- Expose ports **80 (HTTP)** and **443 (HTTPS)**.
- Set `SERVER_DOMAIN=example.com`, which will be used inside the container.
- Set `ADMIN_EMAIL=admin@example.com` as the admin email for configurations.

# TODO

- Instead of AWS ECS, this setup uses Portainer.io or another Docker Swarm manager.
- Autoscaling is not possible with the current architecture; needs ECS.
- Improve documentation.
- Document EFS issues and workarounds using Syncthing.
