class_name NameBlocklist
extends RefCounted
## Data for NameFilter: the words a player name may not contain. Plain lowercase letters only (the
## filter folds case, accents and leetspeak first). A separate file so the list can grow without
## touching the matching code; it is a script, not a text file, so it always ships in the export.
##
## Repeated letters in the input are tolerated ("fuuuck" matches "fuck"), but a double letter
## written here must appear at least twice ("ass" does not match "as", "nigger" not "niger").

## Severe words that are blocked wherever they appear, also with spaces or symbols between the
## letters ("f u c k", "xx_fuck_xx"). Only words with no innocent word around them belong here.
const SUBSTRINGS: PackedStringArray = [
	"fuck", "nigger", "faggot", "bitch", "pussy", "cocksuck", "blowjob", "motherfuck", "cumshot",
]

## Blocked as a whole word (a space-separated piece of the name). The word may carry one prefix and
## one suffix from the two lists below, and two blocked words may be glued together ("assdick").
## That catches "dumbass" and "dicks" but not "Scunthorpe", "Cassie", "Dickens" or "Assess".
const WORDS: PackedStringArray = [
	"shit", "shitty", "shitting", "shithead", "cunt", "dick", "cock", "ass", "asshole", "arse", "arsehole",
	"bastard", "whore", "slut", "nigga", "fag", "retard", "retarded", "spic", "chink", "kike", "coon",
	"tranny", "shemale", "dyke", "wetback", "beaner", "gook", "paki", "twat", "wank", "wanker",
	"wanking", "bollock", "bollocks", "prick", "piss", "pissed", "pissing", "cum", "jizz", "jizzed", "rape",
	"raped", "raping", "rapist", "nazi", "hitler", "kkk", "porn", "penis", "vagina", "anus", "boob",
	"boobie", "tit", "titty", "pedo", "pedophile", "paedo", "molest", "molester", "dildo", "handjob",
	"slag", "skank", "clit", "fck", "fuk", "fuq", "sht", "cnt", "btch",
]

## Words that may sit in front of a blocked word ("dumbass", "bullshit", "motherfucker").
const PREFIXES: PackedStringArray = [
	"mother", "dumb", "fat", "big", "lil", "stupid", "bull", "horse", "jack", "smart", "wise", "bad",
]

## Endings that may follow a blocked word ("dicks", "asses", "dickhead").
const SUFFIXES: PackedStringArray = [
	"s", "es", "head", "heads", "face", "hole", "holes", "bag", "wad", "lord", "boy", "hat", "wipe",
	"clown", "munch",
]
