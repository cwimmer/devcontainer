# syntax=docker/dockerfile:1
FROM public.ecr.aws/ubuntu/ubuntu:24.04_stable
ARG ASDF_VERSION=v0.19.0
ARG BATS_VERSION=1.13.0
ARG DOCTL_VERSION=1.155.0
ARG GOLANG_VERSION=1.26.2
ARG HELM_VERSION=4.1.4
ARG KIND_VERSION=0.31.0
ARG KUBECTX_VERSION=0.11.0
ARG KUBECTL_VERSION=1.36.0
ARG TERRAFORM_DOCS_VERSION=0.22.0
ARG TERRAFORM_VERSION=1.14.9
ARG TFLINT_VERSION=0.62.0
ARG TRIVY_VERSION=0.70.0

RUN apt-get update && apt-get install -y \
    unzip \
    curl \
    git \
    make \
    python3-pip \
    pipx \
    jq \
    wget \
    direnv \
    golang-go

RUN GOBIN=/usr/local/bin go install github.com/asdf-vm/asdf/cmd/asdf@$ASDF_VERSION

COPY scripts/.bashrc /tmp/.bashrc
RUN install -D -m 0755 -o root -g root /tmp/.bashrc /root/.bashrc
RUN rm /tmp/.bashrc

ENV PATH="/root/.asdf/bin:/root/.asdf/shims:/root/.local/bin:$PATH"

RUN asdf plugin add terraform
RUN asdf install terraform $TERRAFORM_VERSION

# Install Python-based development tools
RUN pipx install pre-commit
RUN pipx install commitizen  # Tool for creating Conventional Commits

RUN wget https://github.com/digitalocean/doctl/releases/download/v$DOCTL_VERSION/doctl-$DOCTL_VERSION-linux-amd64.tar.gz
RUN tar xf doctl-$DOCTL_VERSION-linux-amd64.tar.gz
RUN install -D -m 0755 -o root -g root doctl /usr/local/bin/
RUN rm doctl-$DOCTL_VERSION-linux-amd64.tar.gz doctl

RUN asdf plugin add kubectl
RUN asdf install kubectl $KUBECTL_VERSION
RUN asdf plugin add terraform-docs https://github.com/looztra/asdf-terraform-docs
RUN asdf install terraform-docs $TERRAFORM_DOCS_VERSION
RUN asdf plugin add tflint https://github.com/skyzyx/asdf-tflint
RUN asdf install tflint $TFLINT_VERSION
RUN asdf plugin add trivy https://github.com/zufardhiyaulhaq/asdf-trivy.git
RUN asdf install trivy $TRIVY_VERSION
RUN asdf plugin add golang https://github.com/asdf-community/asdf-golang.git
RUN asdf install golang $GOLANG_VERSION
RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git
RUN asdf install bats $BATS_VERSION
RUN asdf plugin add helm
RUN asdf install helm $HELM_VERSION
RUN asdf plugin add kind
RUN asdf install kind $KIND_VERSION
RUN asdf plugin add kubectx https://github.com/virtualstaticvoid/asdf-kubectx.git
RUN asdf install kubectx $KUBECTX_VERSION

# Write default asdf tool versions for optional use by consumers.
# See README.md for usage instructions.
RUN printf '%s\n' \
    "golang $GOLANG_VERSION" \
    "bats $BATS_VERSION" \
    "helm $HELM_VERSION" \
    "kind $KIND_VERSION" \
    "kubectx $KUBECTX_VERSION" \
    "kubectl $KUBECTL_VERSION" \
    "terraform $TERRAFORM_VERSION" \
    "terraform-docs $TERRAFORM_DOCS_VERSION" \
    "tflint $TFLINT_VERSION" \
    "trivy $TRIVY_VERSION" \
    > /usr/local/share/asdf-tool-versions

# Record build timestamp in an OS-release style file.
# This creates /etc/cwimmer-info containing a single line like:
# BUILD_DATE=2026-02-20T14:23:00+00:00
RUN date -u --iso-8601=seconds | awk '{print "BUILD_DATE="$0}' > /etc/cwimmer-info
