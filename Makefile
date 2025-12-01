.PHONY: all $(MAKECMDGOALS)

build:
	docker build -t calculator-app .
	docker build -t calc-web ./web

server:
	docker run --rm --name apiserver --network-alias apiserver --env PYTHONPATH=/opt/calc --env FLASK_APP=app/api.py -p 5000:5000 -w /opt/calc calculator-app:latest flask run --host=0.0.0.0

test-unit:
	docker rm -f unit-tests || true
	mkdir -p results
	docker run --name unit-tests 		-v `pwd`/results:/opt/calc/results 		--env PYTHONPATH=/opt/calc 		-w /opt/calc calculator-app:latest 		pytest --cov --cov-report=xml:results/coverage.xml 		--cov-report=html:results/coverage 		--junit-xml=results/unit_result.xml -m unit
	docker rm unit-tests

test-api:
	docker network rm calc-test-api || true
	docker network create calc-test-api
	docker rm -f apiserver || true
	docker rm -f api-tests || true
	mkdir -p results
	docker run -d --network calc-test-api 		--env PYTHONPATH=/opt/calc --name apiserver 		--env FLASK_APP=app/api.py -p 5000:5000 -w /opt/calc calculator-app:latest 		flask run --host=0.0.0.0
	docker run --network calc-test-api --name api-tests 		-v `pwd`/results:/opt/calc/results 		--env PYTHONPATH=/opt/calc --env BASE_URL=http://apiserver:5000/ 		-w /opt/calc calculator-app:latest 		pytest --junit-xml=results/api_result.xml -m api
	docker stop apiserver || true
	docker rm --force apiserver || true
	docker stop api-tests || true
	docker rm --force api-tests || true
	docker network rm calc-test-api || true

test-e2e:
	docker network rm calc-test-e2e || true
	docker network create calc-test-e2e
	docker rm -f apiserver || true
	docker rm -f calc-web || true
	@if [ ! -f "web/nginx.conf" ]; then 		echo "ERROR: El archivo web/nginx.conf no existe. Por favor créalo antes de continuar."; 		exit 1; 	fi
	docker run -d --rm 		--volume `pwd`:/opt/calc --network calc-test-e2e 		--env PYTHONPATH=/opt/calc --name apiserver 		--env FLASK_APP=app/api.py -p 5000:5000 -w /opt/calc calculator-app:latest 		flask run --host=0.0.0.0
	docker run -d --rm 		--volume `pwd`/web:/usr/share/nginx/html 		--volume `pwd`/web/nginx.conf:/etc/nginx/conf.d/nginx.conf 		--network calc-test-e2e --network-alias calc-web --name calc-web -p 80:80 nginx
	@echo "Esperando que apiserver esté disponible..."
	@for i in 1 2 3 4 5; do 		docker run --rm --network calc-test-e2e curlimages/curl:7.85.0 curl -s http://apiserver:5000/calc/add/1/1 && break || sleep 5; 	done
	@echo "Esperando que calc-web esté disponible..."
	@for i in 1 2 3 4 5; do 		docker run --rm --network calc-test-e2e curlimages/curl:7.85.0 curl -s http://calc-web && break || sleep 5; 	done
	mkdir -p results
	docker run --rm 		--volume `pwd`/test/e2e/cypress.json:/cypress.json 		--volume `pwd`/test/e2e/cypress:/cypress 		--volume `pwd`/results:/results 		--network calc-test-e2e cypress/included:4.9.0 		--browser chrome --reporter junit 		--reporter-options "mochaFile=/results/e2e_result.xml,toConsole=true"
	docker rm --force apiserver || true
	docker rm --force calc-web || true
	docker network rm calc-test-e2e || true

run-web:
	docker run --rm --volume `pwd`/web:/usr/share/nginx/html --volume `pwd`/web/constants.local.js:/usr/share/nginx/html/constants.js --name calc-web -p 80:80 nginx

stop-web:
	docker stop calc-web
