# syntax=docker/dockerfile:1
FROM public.ecr.aws/ubuntu/ubuntu:24.04_stable
ARG ASDF_VERSION=v0.14.1
ARG DOCTL_VERSION=1.119.0
ARG GOLANG_VERSION=1.23.5
ARG KUBECTL_VERSION=1.32.0
ARG TERRAFORM_DOCS_VERSION=0.19.0
ARG TERRAFORM_VERSION=1.10.0
ARG TFLINT_VERSION=0.54.0
ARG TRIVY_VERSION=0.57.1

RUN apt-get update && apt-get install -y \
    unzip \
    curl \
    git \
    make \
    python3-pip \
    pipx \
    jq \
    wget \
    direnv

RUN git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch $ASDF_VERSION

COPY scripts/.bashrc /tmp/.bashrc
RUN install -D -m 0755 -o root -g root /tmp/.bashrc /root/.bashrc
RUN rm /tmp/.bashrc

ENV PATH="/root/.asdf/bin:/root/.asdf/shims:/root/.local/bin:$PATH"

RUN asdf plugin add terraform
RUN asdf install terraform $TERRAFORM_VERSION

RUN pipx install pre-commit

RUN wget https://github.com/digitalocean/doctl/releases/download/v$DOCTL_VERSION/doctl-$DOCTL_VERSION-linux-amd64.tar.gz
RUN tar xf doctl-$DOCTL_VERSION-linux-amd64.tar.gz
RUN install -D -m 0755 -o root -g root doctl /usr/local/bin/
RUN rm doctl-$DOCTL_VERSION-linux-amd64.tar.gz doctl

RUN asdf plugin add kubectl
RUN asdf install kubectl $KUBECTL_VERSION
RUN asdf plugin-add terraform-docs https://github.com/looztra/asdf-terraform-docs
RUN asdf install terraform-docs $TERRAFORM_DOCS_VERSION
RUN asdf plugin-add tflint https://github.com/skyzyx/asdf-tflint
RUN asdf install tflint $TFLINT_VERSION
RUN asdf plugin add trivy https://github.com/zufardhiyaulhaq/asdf-trivy.git
RUN asdf install trivy $TRIVY_VERSION
RUN asdf plugin add golang https://github.com/asdf-community/asdf-golang.git
RUN asdf install golang $GOLANG_VERSION