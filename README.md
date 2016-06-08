# shavit's jailbreak

- [x] basic LRs
    - [x] colored beacons
    - [x] beacon sounds
    - [x] lr menu
    - [x] initialize lr
    - [x] abort lr


- [x] advanced LRs
    - [x] save pre-lr weapons and give them to the winner
    - [x] abort on disconnect


- [x] sounds
    - [x] on lr activated (lr_activated.mp3)
    - [x] on lr aborted (lr_error.mp3)
    - [x] on lr started (lr_start.mp3)
    - [x] on custom lrs (lr_wow.mp3/lr_hax.mp3)


- [ ] games
    - [x] dodgeball - tested in CS:S
    - [x] shot4shot - tested in CS:S and working
    - [x] random - 500-2500hp, random weapon depending on game, 0.5x-1.5x speed, 0.75x-1.25x gravity
    - [x] noscope battle (random weapon, depending on game)
    - [x] grenade fight
    - [x] backstabs
    - [x] pro90
    - [x] headshots
    - [x] jumpshots (scout/ssg and usp/usp-s)
    - [x] russian roulette
    - [x] knife fight
    - [x] mag4mag
    - [x] flamethrower - random colors owo
    - [x] hax fight
    - [x] gun toss
    - [x] shotgun wars with cool effects like hellsgamers
    - [x] rebel
    - [ ] molotov fight
    - [ ] freeday/vip (needs JBaddons2 API)
    - [ ] race


- [x] rankings
    - [x] count lr wins - need more than 10 active players
    - [x] sm_top/sm_lrtop commands


- [x] starting weapons (t - knife / ct - m4a1/deagle)


- [x] api
    - [x] LRTypes Javit_GetClientLR(int client)
    - [x] void Javit_GetLRName(LRTypes lr, char[] buffer, int maxlen)
    - [x] int Javit_GetClientPartner(int client) // get lr partner
    - [x] void Javit_OnLRAvailable()
    - [x] bool Javit_OnLRStart(LRTypes type, int prisoner, int guard) - return false to not allow the lr to start
    - [x] void Javit_OnLRFinish(LRTypes type, int winner, int loser)
