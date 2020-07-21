#!/usr/bin/env bash

# Don't forget to install the "fabric" toolset by https://github.com/lbroudoux/openshift-cases.git from "software-factory/"

for suite in dev test prod; do
	oc new-project coolstore-$suite
	oc process -f openshift/coolstore-template.yaml | oc create -f -
	oc process -f openshift/coolstore-template.inventory.$suite.yaml | oc create -f -
	oc -n coolstore-$suite policy add-role-to-user edit system:serviceaccount:fabric:jenkins
done

oc process -f inventory-pipeline.yaml -p DEV_PROJECT=coolstore-dev -p TEST_PROJECT=coolstore-test -p PROD_PROJECT=coolstore-prod  | oc -n fabric create -f -

