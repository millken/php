FROM alpine:3.12

ENV PHP_VERSION 7.4.9
ENV SWOOLE_VERSION 4.4.16
ENV REDIS_VERSION 4.1.1
ENV MSGPACK_VERSION 2.1.1
ENV COMPOSER_VERSION 1.10.10

ENV PHP_EXTRA_CONFIGURE_ARGS --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --disable-cgi

ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

LABEL Maintainer="millken <millken@gmail.com>" \
      Description="Lightweight php ${PHP_VERSION} container based on alpine with Composer installed and swoole installed." 

RUN set -x \
	&& addgroup -g 82 -S www-data \
	&& adduser -u 82 -D -S -G www-data www-data

ENV PHP_INI_DIR="/usr/local/etc/php"
RUN mkdir -p ${PHP_INI_DIR}/conf.d

# persistent / runtime deps
RUN set -ex \
	#&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
  	&& apk update \
	&& apk add --no-cache --virtual .persistent-deps \
		curl \
		tar \
		xz \
		libpq \
		libxml2 \
		hiredis \
		libstdc++ \
		sqlite-libs \
		oniguruma \
		brotli-libs \
		tzdata 		
RUN set -ex \
	&& cd /tmp/ \
	#&& wget http://mirrors.sohu.com/php/php-7.4.9.tar.xz \
	&& wget http://www.php.net/distributions/php-${PHP_VERSION}.tar.xz \
	&& tar xf php-${PHP_VERSION}.tar.xz \
	&& apk add --no-cache --virtual .build-deps git mysql-client curl-dev oniguruma-dev openssh-client libffi-dev postgresql-dev hiredis-dev zlib-dev icu-dev libxml2-dev freetype-dev libpng-dev libjpeg-turbo-dev g++ make autoconf sqlite-dev \
	&& export CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS" \
    && cd /tmp/php-${PHP_VERSION} \
    && ./configure --enable-inline-optimization --prefix=/usr/local --with-config-file-path="${PHP_INI_DIR}" --enable-opcache --with-config-file-scan-dir="${PHP_INI_DIR}/conf.d"  --enable-posix  --enable-sysvshm --enable-sysvsem --enable-sigchild --enable-mbstring --with-iconv  --with-pdo-pgsql -with-pdo-mysql -with-pgsql=/usr/local/pgsql  --with-zlib-dir=/usr/include/ --enable-bcmath --with-openssl --enable-pdo --enable-session --enable-tokenizer --enable-json --disable-debug --disable-short-tags --disable-ipv6 --enable-option-checking=fatal --with-mhash --with-curl --without-sqlite3 \
	$PHP_EXTRA_CONFIGURE_ARGS \
    && make -j8 \
	&& make install \
	&& make clean \
	&& mkdir -p ${PHP_INI_DIR}/conf.d \
	&& cd /tmp/ \	
    && wget https://github.com/swoole/swoole-src/archive/v${SWOOLE_VERSION}.tar.gz \
	&& tar xf v${SWOOLE_VERSION}.tar.gz \
	&& unlink v${SWOOLE_VERSION}.tar.gz \
	&& cd /tmp/swoole-src-${SWOOLE_VERSION} \
	&& phpize \
	&& ./configure --enable-openssl --enable-http2 --enable-sockets=/usr/local/include/php/ext/sockets \
	&& make -j8 && make install \
	&& echo 'extension=swoole.so' > ${PHP_INI_DIR}/conf.d/swoole.ini \
	\
	&& cd /tmp/ \
    && wget http://pecl.php.net/get/msgpack-${MSGPACK_VERSION}.tgz \
	&& tar xf msgpack-${MSGPACK_VERSION}.tgz \
	&& cd /tmp/msgpack-${MSGPACK_VERSION} \
	&& phpize \
	&& ./configure \
	&& make -j8 && make install \
	&& echo 'extension=msgpack.so' > ${PHP_INI_DIR}/conf.d/msgpack.ini \
	\
	&& cd /tmp/ \	
    && wget https://github.com/swoole/ext-async/archive/v${SWOOLE_VERSION}.tar.gz \
	&& tar xf v${SWOOLE_VERSION}.tar.gz \
	&& unlink v${SWOOLE_VERSION}.tar.gz \
	&& cd /tmp/ext-async-${SWOOLE_VERSION} \
	&& phpize \
	&& ./configure \
	&& make -j8 && make install \
	&& echo 'extension=swoole_async.so' > ${PHP_INI_DIR}/conf.d/swoole_async.ini \
	\
	&& cd /tmp/ \
    &&  wget https://github.com/laruence/yac/archive/master.zip \
	&& unzip master.zip \
	&& unlink master.zip \
	&& cd /tmp/yac-master \
	&& phpize \
	&& ./configure --enable-msgpack \
	&& make && make install \
	&& { \
		echo 'extension=yac.so'; \
		echo 'yac.enable_cli=1'; \
		echo 'yac.serializer=msgpack'; \
	} | tee > ${PHP_INI_DIR}/conf.d/yac.ini \
	\	
	&& cd /tmp/ \
    && wget http://pecl.php.net/get/redis-${REDIS_VERSION}.tgz \
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
	&& wget https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar \
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
