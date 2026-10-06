class_name BillingBackend
extends RefCounted
## What Entitlement needs from a store. BillingAndroid talks to Google Play; BillingFake stands in on
## desktop, in tests and when the plugin is missing. A backend never decides what the player may do:
## it only reports what the store says (`ownership`), the price, and how a purchase attempt ended
## (`outcome`). Entitlement turns that into the cache and the `changed` signal.

## How a purchase or restore attempt ended.
enum Outcome {
	SUCCESS,      ## owned now (an `ownership(true)` was emitted just before)
	PENDING,      ## paid but not settled yet (cash, bank transfer, parental approval): do NOT unlock
	CANCELLED,    ## the player backed out of the Play sheet
	UNAVAILABLE,  ## no store (plugin missing, release build without billing, Play services missing)
	NETWORK,      ## offline / store unreachable
	NOT_FOUND,    ## a restore found no purchase for this account
	ERROR,        ## anything else
}

## The store's answer to "what does this account own?". `owned == false` is only sent after a
## *successful* query, so a failed query never takes the unlock away.
signal ownership(owned: bool)
## The store's localized price ("$3.99", "3,99 EUR").
signal price(text: String)
## The end of a purchase / restore attempt (see Outcome).
signal outcome(kind: int)
## The purchase token of the owned full game. Emitted just BEFORE `ownership(true)` so a listener that reacts to the
## unlock already has it. Online play sends it to the server (`verifyPurchase`) to set the server-side full flag.
signal purchase_token(token: String)

var _owned_token: String = ""


## The purchase token of the owned `full_unlock` purchase, or "" when none is known (nothing owned, or not queried yet).
func owned_token() -> String:
	return _owned_token


func backend_name() -> String:
	return "none"


## Connects to the store. Safe to call again (reconnects when needed).
func start() -> void:
	pass


## Asks the store what is owned (and the price). Silent: no `outcome` unless something is pending.
func refresh() -> void:
	pass


## Opens the purchase flow for the full game.
func purchase() -> void:
	outcome.emit(Outcome.UNAVAILABLE)


## "Restore purchase": asks the store again and reports SUCCESS or NOT_FOUND.
func restore() -> void:
	outcome.emit(Outcome.UNAVAILABLE)
