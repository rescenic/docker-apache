# Description

DIY AWS Lambda for PHP applications!

Docker image containing Ubuntu 24.04 LTS core with Apache 2.4 and PHP 8.3 + Let's Encyrpt (Optional). This image is designed to be used in AWS environments for high density PHP application hosting. WordPress 5.x and Drupal 10.x and later are tested to work.

# Architecture Overview

* Run multiple EC2 instances across different availability zones to create a redundant docker swarm.
* Cloudwatch alarms must be used to restart failed EC2 instances.
* All EC2 instances must join the docker swarm and mount a common EFS volume on `/srv`.
* Docker container will mount `/srv/example.com/www` as the Apache `DocumentRoot` to serve php applications.
* RDS must be used for hosting databases.
* When this image is run as a docker service in the swarm, a unique port on the host (eg tcp:8001) is mapped to 80 within the container.
* AWS Target Group `example-com` is created with all the EC2 instances of the swarm and specific TCP port (eg tcp:8001) and attached to ALB.
* Docker mesh routing is not cookie/sticky session aware and disabled. HTTP load balancing is fully managed on AWS ALB.
* AWS ALB rules are used to route example.com and www.example.com requests to `example-com` Target Group.
* AWS ALB is also used for HTTPS termination, docker containers provide only vanilla HTTP.
* Outbound emails must be routed via SES (Drupal SMTP module, WP SMTP plugin, etc).
* Apache logs are sent to stdout/stderr and can be routed to AWS Cloudwatch using the docker `awslogs` log driver.

# Filesystem Layout

* `/srv` -- base dir to be published via AWS EFS to all nodes, subdirectories `/srv/example.com`, `/srv/example.net`, etc to be created for each website/domain.
* `/srv/example.com/www` -- root folder for php applications (WordPress root, Drupal root, etc), mounted within docker containers as Apache `DocumentRoot`
* `/srv/example.com/etc/apache` and `/srv/example.com/etc/php` -- optional apache/php config
* `/srv/example.com/mysqlbackup` -- used for storing MySQL dumps

# Small But Significant Things

* Apache MPM prefork is configured to reduce RAM usage, a WordPress 5.x container will idle around 50-75MB of RAM.
* WordPress W3TC plugin cache folder is in `$WP_ROOT/wp-content/cache`. EFS is slow, so it's recommended to move the cache folder inside the docker container. Delete the cache folder and run `ln -s /srv/example.com/www/wp-content/cache /tmp`. Cache folder will be hosted within docker instance and run faster.
* PHP POST max and max file upload size is increased to 1G & 512M to handle large file uploads.
* EFS is slow, to improve performance php opcache revalidation time is increased from default 2 seconds to 300 seconds.
* apache process runs as `www-data`. Inside the docker instance, none of the processes are run as `root`. `setcap` is used to permit non-root apache process to bind to TCP port 80.
* Apache config is aware of SSL termination on AWS ALB or CloudFlare Flexible SSL settings. WordPress site URL can be set to https://www.example.com and SSL termination can be done on AWS ALB or CloudFlare and WordPress will not throw infinite HTTP redirection errors.
* To view the default Apache and PHP config, run the docker image without mapping an external DocumentRoot and access the container via http://localhost:8001/index.php (returns phpinfo) and http://localhost:8001/.config (contains /etc/apache and /etc/php tar files). This can be used for further customization.
* To use custom Apache config, extract the base apache config in `/svr/example.com/etc` and then bind mount it inside the container. Eg. `docker run -v /srv/example.com/etc/php:/etc/php:ro -v /srv/example.com/etc/apache:/etc/apache:ro ...`
* WordPress updates can be handled outside the docker environment via WP-CLI. From an independent EC2 instance, 1) apt install all Apache/PHP WordPress dependencies, 2) mount EFS /srv volume, 3) run `cd /srv/example.com/www && wp-cli plugin update --all`.

# Building

To build:

```bash
docker build --no-cache -t rescenic/php-apache-ubuntu:noble .
```

# Running

## Example 1: Basic usage

Run with internal document root to reveal Apache/PHP config. See http://localhost/index.php and http://localhost/.config/

```bash
docker run --name=test -p 80:80 rescenic/php-apache-ubuntu:noble
```

## Example 2: Testing WordPress

Run a WordPress site from /srv/example.com/www

```bash
docker run --name=example-com -v /srv/example.com/www:/var/www/html -p 80:80 rescenic/php-apache-ubuntu:noble
```

## Example 3: Using custom apache2 and php config

Run a WordPress site from /srv/example.com/www, but this time use custom apache and php config from /srv/example.com/etc/{apache,php}

```bash
docker run --name=example-com -v /srv/example.com/www:/var/www/html -v /srv/example.com/etc/apache2:/etc/apache2:ro -v /srv/example.com/etc/php:/etc/php:ro -p 80:80 rescenic/php-apache-ubuntu:noble
```

## Example 4: Running as a docker service in a docker swarm

Run 2 replicas of the container as a docker service. This command must be run from a docker swarm manager node. AWS ALB and Target Group must be created to route traffic for example.com to this container:

```bash
docker service create --replicas 2 --name example-com --publish published=8000,target=80,mode=host --mount type=bind,source=/srv/example.com/www,destination=/var/www/html rescenic/php-apache-ubuntu:noble
```

## Example 5: Run Let's Encrypt

To enter a running Docker container and edit `000-default-ssl.conf`, follow these steps:

---

### **1. Find the Running Container ID or Name**
Run the following command to list running containers:
```bash
docker ps
```
You'll see an output like this:
```
CONTAINER ID   IMAGE          COMMAND                 CREATED         STATUS         PORTS                    NAMES
abc123def456   my_apache_img  "apache2ctl -D FOR..."  10 minutes ago  Up 10 minutes 80/tcp, 443/tcp          my_apache_container
```
Take note of the **CONTAINER ID** or **NAME** (e.g., `my_apache_container`).

---

### **2. Access the Running Container**
Use `docker exec -it` to open a shell inside the container:
```bash
docker exec -it my_apache_container bash
```
Replace `my_apache_container` with your actual container name or ID.

---

### **3. Edit `000-default-ssl.conf`**
Once inside the container, open the file with a text editor like `nano` or `vi`:
```bash
nano /etc/apache2/sites-available/000-default-ssl.conf
```
or
```bash
vi /etc/apache2/sites-available/000-default-ssl.conf
```

Make the necessary changes and **save the file**:
- In `nano`: Press `CTRL + X`, then `Y`, then `Enter` to save.
- In `vi`: Press `ESC`, type `:wq`, then press `Enter`.

---

### **4. Restart Apache for Changes to Take Effect**
After editing, restart Apache inside the container:
```bash
service apache2 restart
```
or
```bash
apache2ctl restart
```

---

### **Alternative: Copy the Modified File from Host to Container**
If you prefer to edit the file on your local machine and copy it to the container, use:
```bash
docker cp default-ssl.conf my_apache_container:/etc/apache2/sites-available/000-default-ssl.conf
```
Then restart Apache as mentioned earlier.

---

### **5. Exit the Container**
Once done, type:
```bash
exit
```
This will return you to your host machine.


# TODO

* Instead of AWS ECS, this setup uses portainer.io or other docker swarm manager.
* Autoscaling is not possible with current architecture, needs ECS.
* Improve documentation.
* Documentation for EFS issues and workaround using syncthing. 
