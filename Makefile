.DEFAULT_GOAL := run
.PHONY: run stop

run:
	sh with-secrets.sh docker compose up -d

stop:
	docker compose down
