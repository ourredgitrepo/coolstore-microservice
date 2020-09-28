## Internal notes

First, read the [official openshift install howto](https://docs.openshift.com/container-platform/4.5/installing/installing_azure/installing-azure-account.html)

Service Principal: `http://openshift_sp`

... the master nodes as the user `core`

cluster name: osdemo

```
INFO Install complete!
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/fules/src/openshift_aws/02_openshift_4.1_on_azure/cluster_install/auth/kubeconfig'
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.osdemo.az.wodeewa.com
INFO Login to the console with user: "kubeadmin", and password: "**********"
INFO Time elapsed: 57m27s
```

## Demo project #1: sclorg mongo+js demo

The 5.4 cli `oc new app` by default creates deployments and not deploymentconfigs, so
the process in the docs doesn't work.

Either use 5.1 cli, or modify the `oc set env dc/whatever` to `oc set env deployment/whatever`.

Except for that, it works.


## Demo project #2/a: coolstore - by LBroudoux

NOTE: It's half fake. Its 'fabric' project (gogs, jenkins, nexus) is fine, its 'msa-store-dev' project
uses a mocked code, where the inventory is just a js array in index.html, the ip address of the order
service is hardwired, the ui doesn't send an 'Origin:' header so the order service rejects it with CORS error,
etc.

https://github.com/lbroudoux/openshift-msa-store

And there are troubles with the AMQ imagestream setup.

The AMQ 7.4 imagestream install is [here](https://access.redhat.com/documentation/en-us/red_hat_amq/7.4/html-single/deploying_amq_broker_on_openshift_container_platform/index#install-deploy-broker-ocp)

```
git clone https://github.com/lbroudoux/openshift-cases.git
cd openshift-cases/software-factory
vim create-fabrique.sh
	DOMAIN="" -> DOMAIN="apps.osdemo.az.wodeewa.com"
vim gogs-persistent-template.yaml
	9.5 -> 9.6
	(Builds / ImageStreams / Project: openshift / filter: postgresql, pick the oldest version instead of 9.5 above)
sh create-fabrique.sh
```

Check if you can log in with team:team to gogs-fabric.your-domain.com

If not, then "Register" on the web ui: name=team, pwd=team, email=team@gogs.com

```
git clone https://github.com/lbroudoux/openshift-msa-store.git
cd openshift-msa-store
vim provision-demo.sh
	DOMAIN="" -> DOMAIN="apps.osdemo.az.wodeewa.com"
oc new-project msa-store-dev --display-name="MSA Store (DEV)"
sh provision-demo.sh deploy msa-store
```

```
Project: msa-store-dev
Operators / Operator Hub / filter: AMQ, choose: "AMQ Broker"
Install
```

NOTE: It hasn't asked for admin/admin user/pass settings, so they are hardwired or cached somewhere...

The gogs repos all contain only one top-level directory, and all the sources are within that one, and this is not OK, so:

When instantiating catalog items (eg. apache http server for shop-ui), set the "Context Directory" to this top-level directory.


## Demo project #2/b: coolstore - by siamaksade

The same unmaintained mess of layers as before.


## Demo project #2/c: coolstore - by jbosscentral, the original one

The source is [here](https://github.com/jbossdemocentral/coolstore-microservice).

The manual install ~works right out of the box~ fails because some hardwired versions of some bower packages have become obsolete and are no longer available.

We forked the repo and fixed them [here](https://github.com/ourredgitrepo/coolstore-microservice). But you already know that as this file is here as well.


Don't forget to install the "fabric" toolset from the repo of [LBrodoux](https://github.com/lbroudoux/openshift-cases.git)

### Nexus repos

Now the Coolstore installer just fetches the packages from the original repos, because they aren't mirrored in our Nexus, and because it's not
configured to use our Nexus.

!!! Work in progress !!!  I'm trying to have the repos mirrored, but it's not ready yet!

[Here](https://raw.githubusercontent.com/OpenShiftDemos/nexus/master/scripts/nexus-functions) are they configured:

- By LBroudoux: `add_nexus2_redhat_repos`
- By SiamakSade: `add_nexus3_redhat_repos`

These two repos are not (yet) configured:
```
		-p NPM_MIRROR=http://nexus-fabric.apps.osdemo.az.wodeewa.com/repository/npm/
		-p BOWER_MIRROR=http://nexus-fabric.apps.osdemo.az.wodeewa.com/repository/bower-mirror/
```

And this one is configured, but to some different source repo, as it doesn't find all packages it needs:
```
		-p MAVEN_MIRROR_URL=http://nexus-fabric.apps.osdemo.az.wodeewa.com/content/groups/public/
```

So the Nexus with this config is completely unusable for us...

See install.sh for this:

```
for suite in dev test; do
	oc new-project coolstore-$suite
	oc process -f openshift/coolstore-template.yaml | oc create -f -
done
```


## The big picture of Coolstore

There are a lot of buildconfigs here: `cart`, `catalog`, `coolstore-gw`, `pricing`, `rating`, `review`, `web-ui`.
And `inventory`, but that's special, you'll see why.

All these buildconfigs eat sources and produce new images into their respective imagestreams.

There are deploymentconfigs with these names as well, they take the latest images from the
imagestreams and deploy pods based on them.

There are services created for them as well, and for the `coolstore-gw` and `web-ui` also routes, too.

This nice bunch of things make up an environment, like a "development" or "test" environment,
so we have three projects: `coolstore-dev`, `coolstore-test` and `coolstore-prod`.

And each project has its own zoo of the abovementioned buildconfigs, deploymentconfigs, etc.

Some of these thingies have separate backends, like `inventory-postgresql` or `catalog-mongodb`,
which aren't _built_, so they don't have buildconfigs, but they are deployed, so they have
deploymentconfigs, and they are accessed, so they have services as well (and of course pods, too).

That would be a nice uniform picture, wouldn't it... So, here comes the "...except for..." part :D

The inventory component in the `coolstore-prod` project is different: here we want to support some
blue-green testing.

The inventory in all three projects has imagestream and one `inventory-postgresql`, but the rest is different.

In `coolstore-dev` there is a buildconfig for `inventory`, which feeds the imagestream with images tagged as
`coolstore-dev/inventory:latest`. This triggers the `inventory` deploymentconfig here, so that's just like
the other components.

In `coolstore-test` there is no buildconfig for `inventory`, but there is one deploymentconfig, which is
triggered by `coolstore-test/inventory:test` tagged images in the imagestream.

This tag is put on the new images by the jenkins pipeline, whenever a build has successfully completed
on `coolstore-dev`.

On `coolstore-prod` there is also no buildconfig for inventory, but there are two deploymentconfigs:
`inventory-blue` and `inventory-green`, triggered by images tagged as `coolstore-prod/inventory:prod-blue` and
`coolstore-prod/inventory:prod-green`.

(NOTE: The deploymentconfigs refer only to tags within the same project, so the `coolstore-qwer/` prefixes
aren't needed.)

The two separate deploymentconfigs deploy two separate pods, which have two separate services, also called
`inventory-blue` and `inventory-green`.

But in addition to this, there is a route as well, called just `inventory`, which points to either the `-blue` or to
the `-green` service.

So the control of this blue-green switching means:
- triggering a build in `coolstore-dev`
- waiting for it to complete successfully (tagged as `coolstore-dev/inventory:latest`)
- adding the tag `coolstore-test/inventory:test` to the image
- waiting for the image to deploy in test
- here should happen the testing, now it is mocked with a 10 seconds wait
- the user is asked to go live or abort
- in case of go live, adding the tag `coolstore-prod/inventory:prod-blue` (or `-green`)
- waiting for the image to deploy in `coolstore-prod` as `inventory-blue`
- toggle the route to the appropriate service
- toggle the next build between blue and green

All this is done by a jenkins pipeline, which is created by the buildconfig `inventory-pipeline` in the fabric project.
