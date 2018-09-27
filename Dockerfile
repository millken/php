FROM alpine:3.7

ENV TIMEZONE Asia/Shanghai
ENV PHP_VERSION 7.2.10
ENV PROTOBUF_VERSION 3.6.1
ENV REDIS_VERSION 4.1.1
ENV SWOOLE_VERSION 4.2.1
ENV YAC_VERSION 2.0.2
ENV COMPOSER_VERSION 1.7.2

ENV PHP_EXTRA_CONFIGURE_ARGS --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --disable-cgi

ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

LABEL Maintainer="millken <millken@gmail.com>" \
      Description="Lightweight php 7.2 container based on alpine with Composer installed and swoole installed." 

RUN set -x \
	&& addgroup -g 82 -S www-data \
	&& adduser -u 82 -D -S -G www-data www-data

ENV PHP_INI_DIR="/usr/local/etc/php"
RUN mkdir -p ${PHP_INI_DIR}/conf.d

# persistent / runtime deps
RUN set -ex \
	&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.shu.edu.cn/g' /etc/apk/repositories \
  	&& apk update \
	&& apk add --no-cache --virtual .persistent-deps \
		curl \
		tar \
		xz \
		libpq \
		libxml2 \
		hiredis \
		libstdc++ \
		tzdata \
	&& echo "${TIMEZONE}" > /etc/timezone \ 
	&& ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime 		
RUN set -ex \
	&& cd /tmp/ \
	&& ([ -f /tmp/php-${PHP_VERSION}.tar.xz ] || wget http://hk2.php.net/distributions/php-${PHP_VERSION}.tar.xz) \
	&& tar xf php-${PHP_VERSION}.tar.xz \
	&& apk add --no-cache --virtual .build-deps git mysql-client curl-dev openssh-client libffi-dev postgresql-dev hiredis-dev zlib-dev icu-dev libxml2-dev freetype-dev libpng-dev libjpeg-turbo-dev g++ make autoconf \
	&& export CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS" \
    && cd /tmp/php-${PHP_VERSION} \
    && ./configure --enable-inline-optimization --prefix=/usr/local --with-config-file-path="${PHP_INI_DIR}" --enable-opcache --with-config-file-scan-dir="${PHP_INI_DIR}/conf.d"  --enable-posix  --enable-sysvshm --enable-sysvsem --enable-sigchild --enable-mbstring --with-iconv  --with-pdo-pgsql -with-pdo-mysql -with-pgsql=/usr/local/pgsql  --with-zlib-dir=/usr/include/ --enable-bcmath --with-openssl --enable-pdo --enable-session --enable-tokenizer --enable-hash --enable-json --disable-debug --disable-short-tags --disable-ipv6 --enable-option-checking=fatal --with-mhash --with-curl \
	$PHP_EXTRA_CONFIGURE_ARGS \
    && make -j8 \
	&& make install \
	&& make clean \
	&& cd /tmp/ \	
    && ([ -f /tmp/swoole-${SWOOLE_VERSION}.tgz ] || wget http://pecl.php.net/get/swoole-${SWOOLE_VERSION}.tgz) \
	&& tar xf swoole-${SWOOLE_VERSION}.tgz \
	&& cd /tmp/swoole-${SWOOLE_VERSION} \
	&& phpize \
	&& ./configure --enable-async-redis --enable-openssl --enable-coroutine-postgresql --enable-sockets=/usr/local/include/php/ext/sockets \
	&& make -j8 && make install \
	&& echo 'extension=swoole.so' > ${PHP_INI_DIR}/conf.d/swoole.ini \
	\
	&& cd /tmp/ \
    && ([ -f /tmp/protobuf-${PROTOBUF_VERSION}.tgz ] || wget http://pecl.php.net/get/protobuf-${PROTOBUF_VERSION}.tgz) \
	&& tar xf protobuf-${PROTOBUF_VERSION}.tgz \
	&& cd /tmp/protobuf-${PROTOBUF_VERSION} \
	&& phpize \
	&& ./configure \
	&& make -j8 && make install \
	&& echo 'extension=protobuf.so' > ${PHP_INI_DIR}/conf.d/protobuf.ini \
	\
	&& cd /tmp/ \
    && ([ -f /tmp/yac-${YAC_VERSION}.tgz ] || wget http://pecl.php.net/get/yac-${YAC_VERSION}.tgz) \
	&& tar xf yac-${YAC_VERSION}.tgz \
	&& cd /tmp/yac-${YAC_VERSION} \
	&& phpize \
	&& ./configure \
	&& make && make install \
	&& { \
		echo 'extension=yac.so'; \
		echo 'yac.enable_cli=1'; \
	} | tee > ${PHP_INI_DIR}/conf.d/yac.ini \
	\	
	&& cd /tmp/ \
    && ([ -f /tmp/redis-${REDIS_VERSION}.tgz ] || wget http://pecl.php.net/get/redis-${REDIS_VERSION}.tgz) \
	&& tar xf redis-${REDIS_VERSION}.tgz \
	&& cd /tmp/redis-${REDIS_VERSION} \
	&& phpize \
	&& ./configure \
	&& make -j8 && make install \
	&& echo 'extension=redis.so' > ${PHP_INI_DIR}/conf.d/redis.ini \
	\
	&& { \
				echo 'zend_extension=opcache.so'; \
                echo 'opcache.memory_consumption=128'; \
                echo 'opcache.interned_strings_buffer=8'; \
                echo 'opcache.max_accelerated_files=4000'; \
                echo 'opcache.revalidate_freq=60'; \
                echo 'opcache.fast_shutdown=1'; \
                echo 'opcache.enable_cli=1'; \
    } | tee > ${PHP_INI_DIR}/conf.d/opcache.ini \
	&& cd /tmp/ \
	&& ([ -f /tmp/composer.phar ] || wget https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar) \
    && cp /tmp/composer.phar /usr/local/bin/composer \
    && chmod +x /usr/local/bin/composer \
    && apk del .build-deps \
    && rm -rf /tmp/* 

RUN set -ex \
	&& cd /usr/local/etc \
	&& sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null \
	&& cp php-fpm.d/www.conf.default php-fpm.d/www.conf \
	&& { \
		echo '[global]'; \
		echo 'error_log = /proc/self/fd/2'; \
		echo; \
		echo '[www]'; \
		echo '; if we send this to /proc/self/fd/1, it never appears'; \
		echo 'access.log = /proc/self/fd/2'; \
		echo; \
		echo 'clear_env = no'; \
		echo; \
		echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
		echo 'catch_workers_output = yes'; \
	} | tee php-fpm.d/docker.conf \
	&& { \
		echo '[global]'; \
		echo 'daemonize = no'; \
		echo; \
		echo '[www]'; \
		echo 'listen = 9000'; \
	} | tee php-fpm.d/zz-docker.conf

	
RUN mkdir -p /var/www/html

WORKDIR /var/www/html

VOLUME ["/var/www"]

EXPOSE 9000

CMD ["/bin/sh"]
