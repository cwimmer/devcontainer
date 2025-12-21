CONTAINER_NAME:=ghcr.io/cwimmer/devcontainer
TAG:=latest
.PHONY: test
test: Dockerfile builder
	docker buildx build \
	--platform linux/amd64,linux/arm64 \
	--tag $(CONTAINER_NAME):$(TAG) .
	docker buildx build --load \
	--platform linux/arm64 \
	--tag $(CONTAINER_NAME):$(TAG) .

.PHONY: builder
builder:
	docker buildx inspect builder || docker buildx create --name builder
	docker buildx use builder
	docker buildx inspect --bootstrap

.PHONY: clean
clean:
	docker buildx rm builder
	docker rmi $(CONTAINER_NAME):$(TAG)

test_native: Dockerfile builder
	docker buildx build --load \
	--tag $(CONTAINER_NAME):$(TAG) .

pre-commit:
	pre-commit install
	pre-commit autoupdate
	pre-commit run --all-files

.PHONY: upgrade
upgrade:
	@echo "Updating Dockerfile to latest tool versions..."
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

.PHONY: upgrade-asdf
upgrade-asdf:
	@echo "Updating asdf version in Dockerfile..."
	@bash scripts/update-versions.sh --tool asdf
