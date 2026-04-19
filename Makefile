CONTAINER_NAME:=ghcr.io/cwimmer/devcontainer
TAG:=latest
OPENCODE_TAG:=opencode
OPENCODE_DOCKERFILE:=Dockerfile.OpenCode

.PHONY: test
test: Dockerfile builder
	docker buildx build \
	--platform linux/amd64,linux/arm64 \
	--tag $(CONTAINER_NAME):$(TAG) .
	docker buildx build --load \
	--platform linux/arm64 \
	--tag $(CONTAINER_NAME):$(TAG) .
	docker run --rm $(CONTAINER_NAME):$(TAG) cat /usr/local/share/asdf-tool-versions

.PHONY: test_opencode
test_opencode: $(OPENCODE_DOCKERFILE) builder test
	docker buildx build \
	--platform linux/amd64,linux/arm64 \
	--tag $(CONTAINER_NAME):$(OPENCODE_TAG) -f $(OPENCODE_DOCKERFILE) .
	docker buildx build --load \
	--platform linux/arm64 \
	--tag $(CONTAINER_NAME):$(OPENCODE_TAG) -f $(OPENCODE_DOCKERFILE) .
	docker run --rm $(CONTAINER_NAME):$(OPENCODE_TAG) cat /usr/local/share/asdf-tool-versions
	docker run --rm $(CONTAINER_NAME):$(OPENCODE_TAG) opencode --version

.PHONY: builder
builder:
	docker buildx inspect builder || docker buildx create --name builder
	docker buildx use builder
	docker buildx inspect --bootstrap

.PHONY: clean
clean:
	-docker buildx rm builder
	-docker rmi $(CONTAINER_NAME):$(TAG)
	-docker rmi $(CONTAINER_NAME):$(OPENCODE_TAG)

.PHONY: test_native
test_native: Dockerfile builder
	docker buildx build --load \
	--tag $(CONTAINER_NAME):$(TAG) .
	docker run --rm $(CONTAINER_NAME):$(TAG) cat /usr/local/share/asdf-tool-versions

.PHONY: test_native_opencode
test_native_opencode: $(OPENCODE_DOCKERFILE) builder test_native
	docker buildx build --load \
	--tag $(CONTAINER_NAME):$(OPENCODE_TAG) -f $(OPENCODE_DOCKERFILE) .
	docker run --rm $(CONTAINER_NAME):$(OPENCODE_TAG) cat /usr/local/share/asdf-tool-versions
	docker run --rm $(CONTAINER_NAME):$(OPENCODE_TAG) opencode --version

.PHONY: pre-commit
pre-commit:
	pre-commit install
	pre-commit autoupdate
	pre-commit run --all-files

.PHONY: upgrade
upgrade:
	@echo "Updating Dockerfile and Dockerfile.OpenCode to latest tool versions..."
	@bash scripts/update-versions.sh --all

.PHONY: upgrade-terraform
upgrade-terraform:
	@echo "Updating Terraform version in Dockerfile..."
	@bash scripts/update-versions.sh --tool terraform

.PHONY: upgrade-golang
upgrade-golang:
	@echo "Updating Go version in Dockerfile..."
	@bash scripts/update-versions.sh --tool golang

.PHONY: upgrade-kubectl
upgrade-kubectl:
	@echo "Updating kubectl version in Dockerfile..."
	@bash scripts/update-versions.sh --tool kubectl

.PHONY: upgrade-tflint
upgrade-tflint:
	@echo "Updating tflint version in Dockerfile..."
	@bash scripts/update-versions.sh --tool tflint

.PHONY: upgrade-trivy
upgrade-trivy:
	@echo "Updating trivy version in Dockerfile..."
	@bash scripts/update-versions.sh --tool trivy

.PHONY: upgrade-terraform-docs
upgrade-terraform-docs:
	@echo "Updating terraform-docs version in Dockerfile..."
	@bash scripts/update-versions.sh --tool terraform-docs

.PHONY: upgrade-doctl
upgrade-doctl:
	@echo "Updating doctl version in Dockerfile..."
	@bash scripts/update-versions.sh --tool doctl

.PHONY: upgrade-helm
upgrade-helm:
	@echo "Updating helm version in Dockerfile..."
	@bash scripts/update-versions.sh --tool helm

.PHONY: upgrade-kind
upgrade-kind:
	@echo "Updating kind version in Dockerfile..."
	@bash scripts/update-versions.sh --tool kind

.PHONY: upgrade-kubectx
upgrade-kubectx:
	@echo "Updating kubectx version in Dockerfile..."
	@bash scripts/update-versions.sh --tool kubectx

.PHONY: upgrade-asdf
upgrade-asdf:
	@echo "Updating asdf version in Dockerfile..."
	@bash scripts/update-versions.sh --tool asdf

.PHONY: upgrade-nodejs
upgrade-nodejs:
	@echo "Updating Node.js version in Dockerfile.OpenCode..."
	@bash scripts/update-versions.sh --tool nodejs

.PHONY: upgrade-opencode
upgrade-opencode:
	@echo "Updating OpenCode version in Dockerfile.OpenCode..."
	@bash scripts/update-versions.sh --tool opencode
