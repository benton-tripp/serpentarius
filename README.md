## Serpentarius Analysis and Web Application

### Overview

### Web Application

#### Managing App via Digital Ocean Droplet

Set up ssh using `ssh-keygen` on your local machine; copy the public key to the droplet.
From the terminal, call:

```
ssh -i ~/.ssh/<rsa_key> root@droplet_ip
```

To copy files (e.g., .env), call:

```
scp -i ~/.ssh/<rsa_key> /path/to/local/file root@droplet_ip:/path/to/remote/directory
```

To set up the environment:

```
sudo apt install python3-pip python3-venv -y
python3 -m venv env
source env/bin/activate
pip install Flask Flask-SQLAlchemy gunicorn python-dotenv

git clone https://github.com/benton-tripp/serpentarius.git
```

Configure Gunicorn: Ensure your Flask app can be served by Gunicorn, a
Python WSGI HTTP Server for UNIX. Test it by running:

```
cd serpentarius/serpentarius
gunicorn --bind 0.0.0.0:8000 "app:create_app()"
```

Set Up a Web Server: Use Nginx as a reverse proxy to forward requests to Gunicorn. 
Install Nginx and configure it to proxy requests. Then, configure Nginx by editing 
/etc/nginx/sites-available/your_domain and setting up a server block.

Enable the Nginx Server Block: Link your configuration from sites-available to 
sites-enabled and restart Nginx.

```
sudo apt install nginx -y
sudo nano /etc/nginx/sites-available/serpentarius.io
```

Content:

```
server {
    listen 80;
    server_name serpentarius.io www.serpentarius.io;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /static {
        alias ~/serpentarius/serpentarius/app/static;
        expires 30d;
    }
}
```
Test Configuration

```
sudo nginx -t
```


```
sudo ln -s /etc/nginx/sites-available/serpentarius.io /etc/nginx/sites-enabled
sudo systemctl restart nginx
```

Test Your Domain: At this point, accessing your server's IP in a web browser should show 
your Flask app served through Nginx.

Manage DNS (e.g., through NameCheap): Find your domain and select "Manage" next to it. 
Go to the "Advanced DNS" tab. Click "Add New Record", select "A Record", and enter 
your Droplet's IP address. The Host should be set to "@" to point the domain itself. 
You may also want to add a "WWW" A Record or CNAME record pointing to your domain. 
Save Changes. It may take up to 48 hours for DNS changes to propagate globally.

Install Certbot and the Nginx plugin:

```
sudo apt install certbot python3-certbot-nginx -y
```

Obtain and Install SSL Certificate: Run Certbot to automatically obtain and install an 
SSL certificate for your domain.

```
sudo certbot --nginx -d www.serpentarius.io -d serpentarius.io
```

Test Automatic Renewal: Ensure your SSL certificate will auto-renew.

```
sudo certbot renew --dry-run
```

Run your web app

```
cd ~/serpentarius/serpentarius
gunicorn --bind 0.0.0.0:8000 "app:create_app()"
```

Error logs:

```
sudo tail /var/log/nginx/error.log
```




Create Gunicorn systemd Service File:

```
sudo nano /etc/systemd/system/gunicorn.service
```

```
[Unit]
Description=Gunicorn instance to serve my Flask app
After=network.target

[Service]
User=benton
Group=www-data
WorkingDirectory=/home/benton/serpentarius/serpentarius
Environment="PATH=/home/benton/serpentarius/env/bin"
ExecStart=/home/benton/serpentarius/env/bin/gunicorn --workers 1 --bind 0.0.0.0:8000 app:create_app

[Install]
WantedBy=multi-user.target
```

```
sudo systemctl daemon-reload
sudo systemctl enable gunicorn
sudo systemctl start gunicorn
sudo systemctl status gunicorn
```
