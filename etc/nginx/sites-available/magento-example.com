server {
    listen          8080;
#    server_name     skin.magento-example.com media.magento-example.com js.magento-example.com www.magento-example.com magento-example.com;
    server_name     magento-example.com magento-example.com;
    root            /var/www/html/magento-example.com;

    index index.html index.htm index.php;

    pagespeed on;

    # Fixes this issue: https://github.com/pagespeed/ngx_pagespeed/issues/1328
    pagespeed Disallow "*/backoffice/*";

    # Needs to exist and be writable by nginx.  Use tmpfs for best performance.
    # https://developers.google.com/speed/pagespeed/module/faq - used this guide
    # tmpfs /var/ngx_pagespeed_cache tmpfs size=1024m,mode=0775,uid=www-data,gid=www-data 0 0
    # mount /var/ngx_pagespeed_cache
    pagespeed FileCachePath /var/ngx_pagespeed_cache;
    # pagespeed Allow purging for Varnish
    pagespeed DownstreamCachePurgeLocationPrefix http://localhost:80;
    pagespeed DownstreamCacheRebeaconingKey "e8effd6982f8695bf34c83c1d53430bfb10fe567194449a8f4d3ef44a0c7043a";

    # pagespeed EnableFilters ;
    pagespeed EnableFilters canonicalize_javascript_libraries,extend_cache,inline_preview_images,insert_image_dimensions;
    pagespeed EnableFilters resize_mobile_images,rewrite_images,recompress_images,lazyload_images;
    pagespeed EnableFilters insert_dns_prefetch;
    pagespeed EnableFilters local_storage_cache,inline_css,inline_javascript;
    pagespeed EnableFilters prioritize_critical_css;
    # Ensure requests for pagespeed optimized resources go to the pagespeed handler
    # and no extraneous headers get set.
    location ~ "\.pagespeed\.([a-z]\.)?[a-z]{2}\.[^.]{10}\.[^.]+" {
      add_header "" "";
    }
    location ~ "^/pagespeed_static/" { }
    location ~ "^/ngx_pagespeed_beacon$" { }

    access_log  /var/log/nginx/magento-example.com.access.log;
    access_log  /var/log/nginx/magento-example.com.apachestyle.access.log  apachestandard;
    error_log  /var/log/nginx/magento-example.com.error.log;

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt { access_log off; log_not_found off; }
    location = /apple-touch-icon.png { access_log off; log_not_found off; }
    location = /apple-touch-icon-precomposed.png { access_log off; log_not_found off; }
    location ~ /\. { deny  all; access_log off; log_not_found off; }

    # Deny access to specific directories no one
    # in particular needs access to anyways.
    location /app/ { deny all; }
    location /includes/ { deny all; }
    location /lib/ { deny all; }
    location /media/downloadable/ { deny all; }
    location /pkginfo/ { deny all; }
    location /report/config.xml { deny all; }
    location /var/ { deny all; }

location ~* /magmi($|/) {
    auth_basic "Magmi login required";
    auth_basic_user_file /var/www/html/web/nginx/magmi.htpasswd;

    try_files $uri =404;

    fastcgi_split_path_info ^(.+\.php)(/.+)$;

    include         fastcgi_params;
    fastcgi_index   index.php;
    fastcgi_param   SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param   SERVER_NAME $host;
    fastcgi_pass    unix:/var/run/php5-fpm.sock;

#    location ~ \.php$ {
#        echo_exec @phpfpm;
#    }
}

    # Allow only those who have a login name and password
    # to view the export folder. Refer to /etc/nginx/htpassword.
    location /var/export/ {
        auth_basic "Restricted";
        auth_basic_user_file htpasswd;
        autoindex on;
    }

    # Deny all attempts to access hidden files
    # such as .htaccess, .htpasswd, etc...
    location ~ /\. {
         deny all;
         access_log off;
         log_not_found off;
    }

    # This redirect is added so to use Magentos
    # common front handler when handling incoming URLs.
    location @handler {
        rewrite / /index.php;
    }

    # Forward paths such as /js/index.php/x.js
    # to their relevant handler.
    location ~ .php/ {
        rewrite ^(.*.php)/ $1 last;
    }


   location ~ \.php/ {
       rewrite ^(.*\.php)/ $1 last;
   }

# ORIGINAL not working due to url appearing in search bar - http://magento.stackexchange.com/questions/70277/magento-1-9-1-1-puts-url-in-search-field
#    location / {
#        try_files $uri $uri/ /index.php?q=$uri&$args;
#    }

location / {
            try_files $uri $uri/ /index.php?$args;
}

    location ~ \.php$ {
        proxy_intercept_errors on;
        error_page 500 501 502 503 = @fallback;
        fastcgi_buffers 8 256k;
        fastcgi_buffer_size 128k;
        fastcgi_intercept_errors on;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass hhvm;
        autoindex on;
    }
    location @fallback {
        fastcgi_buffers 8 256k;
        fastcgi_buffer_size 128k;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass php;
    }
    location ~* \.(ico|gif|jpe?g|png|svg|eot|otf|woff|woff2|ttf|ogg)$ {
        expires max;
    }
}
