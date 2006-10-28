#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <mozilla/nsCOMPtr.h>
#include <mozilla/nsIObserver.h>
#include <mozilla/nsIObserverService.h>
#include <mozilla/nsIServiceManager.h>
#include <mozilla/nsIHttpChannel.h>

static const char *choose_subject_class(nsISupports *subj
		, const char *topic, void **res) {
	const nsID *id = 0;
	const char *subj_class = 0;

	*res = 0;
	if (!strcmp(topic, "http-on-examine-response")) {
		id = &NS_GET_IID(nsIHttpChannel);
		subj_class = "Mozilla::ObserverService::nsIHttpChannel";
	}

	if (id)
		subj->QueryInterface(*id, res);

	return *res ? subj_class : 0;
}

SV *wrap_subject(void *subj, const char *subj_class) {
	SV *obj_ref;
	SV *obj;

	obj_ref = newSViv(0);
	obj = newSVrv(obj_ref, subj_class);
	sv_setiv(obj, (IV) subj);
	SvREADONLY_on(obj);
	return obj_ref;
}

class MyObserver : public nsIObserver {
public:
	NS_DECL_ISUPPORTS
	NS_DECL_NSIOBSERVER

	SV *callbacks_;
};

NS_IMPL_ISUPPORTS1(MyObserver, nsIObserver)

NS_IMETHODIMP MyObserver::Observe(nsISupports *aSubject
		, const char *aTopic, const PRUnichar *aData)
{
	dSP;
	SV **cb;
	const char *subj_class;
	void *subj;

	cb = hv_fetch((HV *) SvRV(this->callbacks_)
			, aTopic, strlen(aTopic), FALSE);
	if (!cb)
		goto out;

	subj_class = choose_subject_class(aSubject, aTopic, &subj);

	ENTER;
	SAVETMPS;
	PUSHMARK(SP);

	if (subj_class) {
		XPUSHs(sv_2mortal(wrap_subject(subj, subj_class)));
	}

	PUTBACK;
	call_sv(*cb, G_DISCARD);
out:
	return NS_OK;
}

MODULE = Mozilla::ObserverService	PACKAGE = Mozilla::ObserverService::nsIHttpChannel

unsigned int responseStatus(SV *obj)
	PREINIT:
		PRUint32 res;
	CODE:
		((nsIHttpChannel *) SvIV(SvRV(obj)))->GetResponseStatus(&res);
		RETVAL = res;
	OUTPUT:
		RETVAL


MODULE = Mozilla::ObserverService		PACKAGE = Mozilla::ObserverService		

int
Register(cbs)
	SV *cbs;
	INIT:
		nsresult rv;
		nsCOMPtr<MyObserver> obs;
		nsCOMPtr<nsIObserverService> os;
		const char *key;
		I32 klen;
		HV *hv;
	CODE:
		rv = !NS_OK;
		obs = new MyObserver;
		if (!obs)
			goto out_retval;

		os = do_GetService("@mozilla.org/observer-service;1", &rv);
		if (NS_FAILED(rv))
			goto out_retval;

		hv = (HV*) SvRV(cbs);
		hv_iterinit(hv);
		while (hv_iternextsv(hv, (char **) &key, &klen)) {
			rv = os->AddObserver(obs, key, PR_FALSE);
		}
		obs->callbacks_ = newSVsv(cbs);
out_retval:
		RETVAL = (rv == NS_OK);
	OUTPUT:
		RETVAL
