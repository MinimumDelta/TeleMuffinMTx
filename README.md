# TeleMuffinMTx
MT4 'Expert' (bot) that communicates transactions to a telegram channel. This needs to be running on an MT4 client and it will register all trades made on the account regardless of the transaction source (desktop client, web, phone, etc). If multiple orders are closed at the same time it will process and broadcast them all up until the Telegram API call limit.

### Telegram API Limit
There is a call limit for the Telegram API so if you try to do 10+ transactions (open, close, change, etc) in a very short timespan (1-2 seconds) it will broadcast each message until the API limit and then quit sending Telegram messages until the lock is released. This is not possible to circumvent without adding additional bots as a backup buffer -- but there shouldn't be that many calls to a Telegram channel anyway so I don't see this being an issue.

### Telegram Bot Creation
Reference this for Telegram bot creation: https://github.com/dennislwm/MT4-Telegram-Bot-Recon
The above repo is what I based my code on, but that code is ass so I ended up rewriting the entire thing after learning the MT4 language.

### Current issues
* I don't know how to send emojis through the Telegram API. If someone can figure that out and create a pull request (or just DM me on Discord), I'd be grateful.
* Pip count is incorrectly calculated. I'll fix this at a later point, too lazy to do it right now.
