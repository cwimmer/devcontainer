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
	@echo "Updating Dockerfile to latest Terraform version..."
	./scripts/update-dockerfile.sh
