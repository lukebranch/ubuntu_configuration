# BASED ON - http://www.schenkels.nl/2014/12/reverse-proxy-with-odoo-8-nginx-ubuntu-14-04-lts/
upstream odoo8 {
server 127.0.0.1:8069 weight=1 fail_timeout=0;
}

upstream odoo8-im {
server 127.0.0.1:8072 weight=1 fail_timeout=0;
}

# http -> https
server {
   listen 80;
   server_name odoo-with-ssl-example.com www.odoo-with-ssl-example.com;
   rewrite ^(.*) https://$host$1 permanent;
}

server {
    listen          443 ssl http2;
    # listen [::]:80 ipv6only=on;
    server_name     odoo-with-ssl-example.com www.odoo-with-ssl-example.com;
    # root            /opt/odoo/odoo-server;

    # SSL parameters
    ssl on;
    ssl_certificate /etc/nginx/ssl/odoo-with-ssl-example.com/ssl-bundle.crt;
    ssl_certificate_key /etc/nginx/ssl/odoo-with-ssl-example.com/odoo-with-ssl-example.key;
    ssl_session_timeout 30m;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
    ssl_prefer_server_ciphers on;

    ## OCSP Stapling
    resolver 127.0.0.1;
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/nginx/ssl/odoo-with-ssl-example.com/ssl-bundle.crt;

    ## ODOO-Specific Settings
    # Specifies the maximum accepted body size of a client request,
    # as indicated by the request header Content-Length.
    client_max_body_size 5000m;
    # add ssl specific settings
    keepalive_timeout 60;
    # increase proxy buffer to handle some OpenERP web requests
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    #general proxy settings
    # force timeouts if the backend dies
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    proxy_read_timeout 720s;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

    # Gzip
 # Compression

  # Enable Gzip compressed.
  gzip on;

  # Enable compression both for HTTP/1.0 and HTTP/1.1.
  gzip_http_version  1.1;

  # Compression level (1-9).
  # 5 is a perfect compromise between size and cpu usage, offering about
  # 75% reduction for most ascii files (almost identical to level 9).
  gzip_comp_level    5;

  # Don't compress anything that's already small and unlikely to shrink much
  # if at all (the default is 20 bytes, which is bad as that usually leads to
  # larger files after gzipping).
  gzip_min_length    256;

  # Compress data even for clients that are connecting to us via proxies,
  # identified by the "Via" header (required for CloudFront).
  gzip_proxied       any;

  # Tell proxies to cache both the gzipped and regular version of a resource
  # whenever the client's Accept-Encoding capabilities header varies;
  # Avoids the issue where a non-gzip capable client (which is extremely rare
  # today) would display gibberish if their proxy gave them the gzipped version.
  gzip_vary          on;

  # Compress all output labeled with one of the following MIME-types.
  gzip_types
    application/atom+xml
    application/javascript
    application/json
    application/rss+xml
    application/vnd.ms-fontobject
    application/x-font-ttf
    application/x-web-app-manifest+json
    application/xhtml+xml
    application/xml
    font/opentype
    image/svg+xml
    image/x-icon
    text/css
    text/plain
    text/x-component;
  # text/html is always compressed by HttpGzipModule

    # set headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forward-For $proxy_add_x_forwarded_for;
    proxy_set_header X-ODOO-dbfilter "OdooDB";

    # by default, do not forward anything
    proxy_redirect off;
    proxy_buffering off;

    location / {
    proxy_redirect off;
    proxy_pass http://odoo8;
    }

    location /longpolling {
    proxy_pass http://odoo8-im;
    }

    # cache some static data in memory for 60mins.
    # under heavy load this should relieve stress on the OpenERP web interface a bit.
     location /web/static/ {
     proxy_cache_valid 200 60m;
     proxy_buffering on;
     expires 864000;
     proxy_pass http://odoo8;
     # autoindex on;
     }

    access_log  /var/log/nginx/www.odoo-with-ssl-example.com.access.log;
    access_log  /var/log/nginx/www.odoo-with-ssl-example.com.apachestyle.access.log;
    error_log  /var/log/nginx/www.odoo-with-ssl-example.com.error.log;

#    location @fallback {
#        fastcgi_buffers 8 256k;
#        fastcgi_buffer_size 128k;
#        include fastcgi_params;
#        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
#        fastcgi_pass php;
#    }
#    location ~* \.(ico|gif|jpe?g|png|svg|eot|otf|woff|woff2|ttf|ogg)$ {
#       expires max;
#    }
}
