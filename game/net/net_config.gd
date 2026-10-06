class_name NetConfig
extends RefCounted
## Where the online backend lives: the local Firebase emulators (default) or the real project (docs/ARCHITECTURE.md
## section 43). The Firebase *web config* (project id, API key) is not a secret; it is what the build swaps.
##
## Emulator ports are the ones in firebase/firebase.json: Auth 9099, Realtime Database 9000, Functions 5001.
## Inside `firebase emulators:exec` the standard FIREBASE_*_EMULATOR_HOST variables are honoured, and
## CRATERLINE_EMULATOR_HOST replaces the machine (for an Android phone talking to a PC use the PC's LAN address;
## 10.0.2.2 from the Android emulator). CRATERLINE_NET=production forces the production values.

# ---------------------------------------------------------------------------------------------------------------
# OWNER / LEAD: PRODUCTION VALUES GO HERE (docs/FIREBASE_SETUP.md). Empty means "no real project yet".
#   project_id       the Firebase project id, e.g. "craterline-12345"
#   api_key          the "Web API key" of the project (Project settings > General); public, not a secret
#   database_url     the Realtime Database URL, e.g. "https://craterline-12345-default-rtdb.europe-west1.firebasedatabase.app"
#   web_client_id    the OAuth *web application* client id used for Google sign-in (Authentication > Google)
#   functions_region must equal REGION in firebase/functions/src/config.ts ("europe-west1")
# ---------------------------------------------------------------------------------------------------------------
const PRODUCTION_PROJECT_ID: String = ""
const PRODUCTION_API_KEY: String = ""
const PRODUCTION_DATABASE_URL: String = ""
const PRODUCTION_WEB_CLIENT_ID: String = ""
const PRODUCTION_FUNCTIONS_REGION: String = "europe-west1"

## Build switch: the release build sets this to true once the production values above are filled in.
const USE_PRODUCTION: bool = false

const EMULATOR_PROJECT_ID: String = "demo-craterline"
const EMULATOR_API_KEY: String = "fake-api-key"
const EMULATOR_DATABASE_NAMESPACE: String = "demo-craterline-default-rtdb"
const EMULATOR_FUNCTIONS_REGION: String = "europe-west1"
const EMULATOR_HOST: String = "127.0.0.1"
const PORT_AUTH: int = 9099
const PORT_DATABASE: int = 9000
const PORT_FUNCTIONS: int = 5001

var production: bool = false
var project_id: String = EMULATOR_PROJECT_ID
var api_key: String = EMULATOR_API_KEY
## Base URL of the Realtime Database, no trailing slash.
var database_url: String = "http://%s:%d" % [EMULATOR_HOST, PORT_DATABASE]
## Sent as `?ns=` (the emulator needs it; the real database does not).
var database_namespace: String = EMULATOR_DATABASE_NAMESPACE
## Identity Toolkit (sign-up, signInWithIdp) and Secure Token (refresh) base URLs, no trailing slash.
var identity_url: String = "http://%s:%d/identitytoolkit.googleapis.com" % [EMULATOR_HOST, PORT_AUTH]
var token_url: String = "http://%s:%d/securetoken.googleapis.com" % [EMULATOR_HOST, PORT_AUTH]
## Base URL of the callable functions: `<functions_url>/<name>`.
var functions_url: String = "http://%s:%d/%s/%s" % [EMULATOR_HOST, PORT_FUNCTIONS, EMULATOR_PROJECT_ID, EMULATOR_FUNCTIONS_REGION]
var functions_region: String = EMULATOR_FUNCTIONS_REGION
var web_client_id: String = ""


## The emulators on `host` with the ports of firebase/firebase.json.
static func emulator(host: String = EMULATOR_HOST) -> NetConfig:
	var c := NetConfig.new()
	c.identity_url = "http://%s:%d/identitytoolkit.googleapis.com" % [host, PORT_AUTH]
	c.token_url = "http://%s:%d/securetoken.googleapis.com" % [host, PORT_AUTH]
	c.database_url = "http://%s:%d" % [host, PORT_DATABASE]
	c.functions_url = "http://%s:%d/%s/%s" % [host, PORT_FUNCTIONS, EMULATOR_PROJECT_ID, EMULATOR_FUNCTIONS_REGION]
	return c


## The real project. `is_configured()` is false until the constants above are filled in.
static func production_config() -> NetConfig:
	var c := NetConfig.new()
	c.production = true
	c.project_id = PRODUCTION_PROJECT_ID
	c.api_key = PRODUCTION_API_KEY
	c.database_url = PRODUCTION_DATABASE_URL.rstrip("/")
	c.database_namespace = ""
	c.identity_url = "https://identitytoolkit.googleapis.com"
	c.token_url = "https://securetoken.googleapis.com"
	c.functions_region = PRODUCTION_FUNCTIONS_REGION
	c.functions_url = "https://%s-%s.cloudfunctions.net" % [PRODUCTION_FUNCTIONS_REGION, PRODUCTION_PROJECT_ID]
	c.web_client_id = PRODUCTION_WEB_CLIENT_ID
	return c


## What the game uses: the build switch, overridable by the environment (tests, developers).
static func current() -> NetConfig:
	var forced: String = OS.get_environment("CRATERLINE_NET").to_lower()
	if forced == "production" or (forced == "" and USE_PRODUCTION):
		return production_config()
	return from_environment()


## The emulator, with hosts taken from the FIREBASE_*_EMULATOR_HOST variables that `firebase emulators:exec` sets.
static func from_environment() -> NetConfig:
	var host: String = OS.get_environment("CRATERLINE_EMULATOR_HOST")
	var c: NetConfig = emulator(host if host != "" else EMULATOR_HOST)
	var db_host: String = OS.get_environment("FIREBASE_DATABASE_EMULATOR_HOST")
	if db_host != "":
		c.database_url = "http://" + db_host
	var auth_host: String = OS.get_environment("FIREBASE_AUTH_EMULATOR_HOST")
	if auth_host != "":
		c.identity_url = "http://%s/identitytoolkit.googleapis.com" % auth_host
		c.token_url = "http://%s/securetoken.googleapis.com" % auth_host
	var fn_host: String = OS.get_environment("FUNCTIONS_EMULATOR_HOST")
	if fn_host != "":
		c.functions_url = "http://%s/%s/%s" % [fn_host, c.project_id, c.functions_region]
	return c


## True when everything needed to talk to the backend is set (always for the emulator).
func is_configured() -> bool:
	if not production:
		return true
	return project_id != "" and api_key != "" and database_url != ""


## A key that changes when the backend changes, so saved sign-in tokens of one backend are never sent to another.
func endpoint_key() -> String:
	return "%s|%s" % [project_id, identity_url]


func callable_url(function_name: String) -> String:
	return "%s/%s" % [functions_url, function_name]


## `<identity_url>/v1/<method>?key=<api key>`
func identity_endpoint(method: String) -> String:
	return "%s/v1/%s?key=%s" % [identity_url, method, api_key.uri_encode()]


func token_endpoint() -> String:
	return "%s/v1/token?key=%s" % [token_url, api_key.uri_encode()]
