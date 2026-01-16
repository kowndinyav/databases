FROM mysql:8.0

# Switch to root user
USER root

# Install Ruby and dependencies using microdnf (Oracle Linux package manager)
RUN microdnf install -y \
    ruby \
    ruby-devel \
    gcc \
    gcc-c++ \
    make \
    && microdnf clean all

# Install innodb_ruby gem
RUN gem install innodb_ruby

# Keep the original MySQL entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["mysqld"]

