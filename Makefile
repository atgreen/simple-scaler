all:
	@echo "Supported targets:"
	@echo " clean		- clean the source tree"
	@echo " podman-start	- run in podman using test/test-pod.yml"
	@echo " podman-stop	- stop the test pod"
	@echo " run		- run locally"

run:
	sbcl --eval '(pushnew (truename "./src") ql:*local-project-directories* )' \
	     --eval '(ql:register-local-projects)' \
	     --eval '(ql:quickload :simple-scaler)' \
	     --eval '(simple-scaler:start-server)'

podman-start:
	sh test/podman-start.sh

podman-stop:
	-podman pod stop simple-scaler-pod1
	-podman pod rm simple-scaler-pod1
	-podman pod stop simple-scaler-pod2
	-podman pod rm simple-scaler-pod2
	-podman pod stop simple-scaler-pod3
	-podman pod rm simple-scaler-pod3

clean:
	@rm -rf system-index.txt *~
