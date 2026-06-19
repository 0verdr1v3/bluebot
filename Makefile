# bluebot — convenience targets. Config comes from .env (see .env.example).
.PHONY: help deploy doctor up down restart logs ps scale mirror stats clean

PANELS ?= 4

help:
	@echo "bluebot targets:"
	@echo "  make deploy        prepare host, preflight, build & launch (one command)"
	@echo "  make doctor        run preflight checks only"
	@echo "  make up / down     start / stop the stack"
	@echo "  make restart       restart the stack"
	@echo "  make logs          follow viewer logs"
	@echo "  make ps            show container + health status"
	@echo "  make scale PANELS=8  regenerate for N panels and roll the stack"
	@echo "  make mirror        load test: mirror panel #1 to the rest"
	@echo "  make stats         live CPU/mem per panel"
	@echo "  make clean         stop stack and delete per-instance Android data"

deploy:
	./deploy.sh

doctor:
	./scripts/doctor.sh

up:
	docker compose up -d --build

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f viewer

ps:
	docker compose ps

scale:
	python3 scripts/gen_compose.py --count $(PANELS)
	docker compose up -d --build

mirror:
	./scripts/connect.sh && python3 scripts/mirror.py

stats:
	./scripts/stats.sh

clean:
	docker compose down
	rm -rf data/
