FROM quay.io/atgreen/simple-scaler-base:latest
#FROM localhost/simple-scaler-base:latest

COPY . /tmp/src
ARG APP_VERSION=APP_VERSION
ENV APP_VERSION=${APP_VERSION}
RUN APP_SYSTEM_NAME=simple-scaler /usr/libexec/s2i/assemble
CMD DEV_BACKEND=slynk APP_SYSTEM_NAME=simple-scaler APP_EVAL="\"(simple-scaler:start-server)\"" /usr/libexec/s2i/run
