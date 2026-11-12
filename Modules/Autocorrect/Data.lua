local addonName, ns = ...

-- Autocorrect: pure data (no WoW API calls; unit-tested in tests/test_autocorrect.lua). The hand-kept tables: known
-- typos, apostrophe words, word pairs, shorthand to leave alone, place names and the keyboard. The big word list is
-- the generated Words.lua; the rules using all of this are in Rules.lua and Line.lua.

-- "a>b c>d" -> { a = "b", c = "d" }; "_" in a fix is a space (alot>a_lot).
local function Fixes(text)
	local t = {}
	for typo, fix in text:gmatch("(%S+)>(%S+)") do
		t[typo] = fix:gsub("_", " ")
	end
	return t
end

local function Set(text)
	local t = {}
	for word in text:gmatch("%S+") do
		t[word] = true
	end
	return t
end

local function List(text)
	local t = {}
	for word in text:gmatch("%S+") do
		t[#t + 1] = word
	end
	return t
end

-- Common English misspellings and chat typos (lowercase typed form > fix). Checked before any guessing, so a typo
-- that would guess wrong, or is too short to guess (3 letters or less), belongs here.
ns.AUTOCORRECT_TYPOS = Fixes([[
teh>the hte>the taht>that thta>that tht>that waht>what whta>what wnat>want wnt>want wiht>with wtih>with iwth>with
adn>and nad>and fo>of fro>for ofr>for jsut>just juts>just konw>know knwo>know nkow>know liek>like lke>like
becuase>because becasue>because beacuse>because becaus>because ebcause>because cuase>cause agian>again agin>again
aginst>against agianst>against alot>a_lot ofcourse>of_course incase>in_case infact>in_fact aswell>as_well
eachother>each_other atleast>at_least alittle>a_little abit>a_bit everytime>every_time noone>no_one
inspite>in_spite ontop>on_top recieve>receive recieved>received reciept>receipt beleive>believe belive>believe
beleived>believed acheive>achieve acheived>achieved acheivement>achievement acheivements>achievements
achievment>achievement achievments>achievements tommorow>tomorrow tomorow>tomorrow tommorrow>tomorrow
tomorrw>tomorrow yesterady>yesterday definately>definitely definatly>definitely definetly>definitely
defintely>definitely deffinitely>definitely seperate>separate seperately>separately seperated>separated
occured>occurred occuring>occurring occurence>occurrence untill>until unitl>until untli>until wich>which
whcih>which whihc>which wihch>which wierd>weird wierdly>weirdly freind>friend freinds>friends firend>friend
firends>friends thier>their tehir>their tehy>they tehm>them thme>them hten>then tehn>then thn>then truely>truly
begining>beginning beggining>beginning goverment>government enviroment>environment independant>independent
neccessary>necessary neccesary>necessary necesary>necessary noticable>noticeable occassion>occasion
occasionaly>occasionally publically>publicly reccomend>recommend recomend>recommend reccommend>recommend
refered>referred relevent>relevant rember>remember remeber>remember rmember>remember sentance>sentence
similiar>similar succesful>successful sucessful>successful successfull>successful suprise>surprise
suprised>surprised tounge>tongue writting>writing writen>written embarass>embarrass embarassing>embarrassing
existance>existence familar>familiar finaly>finally fianlly>finally foriegn>foreign fourty>forty gaurd>guard
gaurds>guards gaurdian>guardian grammer>grammar happend>happened hapen>happen hapened>happened
hapening>happening harrass>harass immediatly>immediately imediately>immediately interupt>interrupt
knowlege>knowledge libary>library maintainance>maintenance millenium>millennium mischievious>mischievous
mispell>misspell mispelled>misspelled ocur>occur oppurtunity>opportunity persistant>persistent
posession>possession prefered>preferred presance>presence probaly>probably probly>probably realy>really
relaly>really resistence>resistance responsability>responsibility rythm>rhythm shoudl>should shuold>should
sholud>should woudl>would wuold>would wolud>would coudl>could cuold>could sieze>seize speach>speech
strenght>strength stregth>strength tendancy>tendency threshhold>threshold tyrany>tyranny tyrrany>tyranny
vaccum>vacuum vaccuum>vacuum vehical>vehicle visable>visible whereever>wherever wheras>whereas thougth>thought
thoguht>thought thikn>think thnik>think htink>think hting>thing thign>thing thigns>things somthing>something
somehting>something someting>something soemthing>something nothign>nothing nohting>nothing anythign>anything
anyhting>anything everythign>everything evrything>everything everyting>everything eveyone>everyone
everone>everyone somone>someone soemone>someone tiem>time tmie>time itme>item itmes>items peopel>people
poeple>people pepole>people abotu>about baout>about abuot>about aobut>about yuo>you oyu>you yoiu>you yuor>your
yoru>your hwo>how woh>who hwy>why wehre>where whre>where wehn>when whne>when ahve>have hvae>have haev>have
bene>been beign>being doign>doing goign>going giong>going gonig>going makign>making takign>taking
lookign>looking lookng>looking playign>playing plyaing>playing workign>working comign>coming comming>coming
gettign>getting sayign>saying tryign>trying runnign>running waitign>waiting turnign>turning holdign>holding
usign>using useing>using thakns>thanks thnaks>thanks thansk>thanks tahnks>thanks pelase>please plaese>please
pleae>please plase>please sory>sorry maybee>maybe mabye>maybe mayeb>maybe gona>gonna finsih>finish
finsihed>finished fnished>finished dugeon>dungeon dungoen>dungeon dungeion>dungeon dugneon>dungeon quset>quest
qeust>quest qusets>quests qeusts>quests healr>healer helaer>healer haeler>healer tnak>tank tnaks>tanks
gruop>group grup>group gorup>group guidl>guild gulid>guild giuld>guild moutn>mount amror>armor weapn>weapon
weapom>weapon wepaon>weapon wepon>weapon sowrd>sword sheild>shield sheilds>shields mgaic>magic majic>magic
cheif>chief vilage>village vilalge>village tonite>tonight tonihgt>tonight tongiht>tonight tonigth>tonight
minuts>minutes minuites>minutes mintues>minutes secodn>second secnod>second hoepfully>hopefully
hopefuly>hopefully acutally>actually actualy>actually acually>actually basicly>basically basicaly>basically
usualy>usually ususally>usually espeically>especially especialy>especially completly>completely
compleatly>completely totaly>totally exaclty>exactly excatly>exactly exactlly>exactly differnt>different
diffrent>different diferent>different importnat>important improtant>important intresting>interesting
intersting>interesting buisness>business busness>business calender>calendar catagory>category
cemetary>cemetery collegue>colleague commited>committed concious>conscious curiousity>curiosity
decieve>deceive dissapear>disappear dissapoint>disappoint dissapointed>disappointed excercise>exercise
experiance>experience febuary>February gratefull>grateful greatful>grateful guarentee>guarantee hieght>height
heigth>height hygeine>hygiene ignorence>ignorance liason>liaison medeval>medieval medevil>medieval
mideval>medieval miniture>miniature mysterous>mysterious naturaly>naturally ninty>ninety paralell>parallel
parliment>parliament percieve>perceive perseverence>perseverance posible>possible possable>possible
potatoe>potato privelege>privilege priviledge>privilege pronounciation>pronunciation quarentine>quarantine
questionaire>questionnaire rediculous>ridiculous ridiculus>ridiculous restaraunt>restaurant
restuarant>restaurant sargent>sergeant stragety>strategy statergy>strategy tatoo>tattoo tomatoe>tomato
twelth>twelfth unfortunatly>unfortunately unforunately>unfortunately unfortunetly>unfortunately usefull>useful
wellcome>welcome welcom>welcome wonderfull>wonderful yeild>yield youself>yourself yourslef>yourself
myslef>myself mysefl>myself ourselfs>ourselves themselfs>themselves sutff>stuff stuf>stuff alredy>already
allready>already alraedy>already alrady>already awsome>awesome awesom>awesome beautifull>beautiful
beatiful>beautiful beutiful>beautiful carefull>careful chnace>chance chaneg>change chnage>change
cheack>check chekc>check choise>choice chosing>choosing clsoe>close coem>come confrim>confirm
decison>decision desicion>decision diffcult>difficult dificult>difficult eariler>earlier easliy>easily
eaisly>easily enought>enough enoguh>enough evne>even exept>except explaination>explanation fisrt>first
frist>first fromt>from froim>from furhter>further gievn>given giev>give grat>great graet>great gerat>great
haveing>having heared>heard hellp>help hlep>help hepl>help hosue>house houes>house imporve>improve
isntead>instead insted>instead intrest>interest kepp>keep knwon>known laer>later latr>later leanr>learn
lenght>length lsat>last lsit>list litle>little littel>little lokk>look mkae>make amke>make maek>make
meanign>meaning mesage>message messsage>message mroe>more moer>more msut>must nedd>need ened>need
nerver>never nver>never nigth>night ngiht>night nmae>name naem>name nubmer>number numebr>number
obivous>obvious oen>one onyl>only olny>only ohter>other otehr>other ouside>outside palce>place plcae>place
paly>play plya>play playr>player pleyer>player poitn>point pwoer>power porblem>problem probelm>problem
quikc>quick qucik>quick qiuck>quick raeson>reason reasno>reason rigth>right rihgt>right riht>right
saem>same smae>same siad>said sadi>said shcool>school smal>small sned>send snet>sent soem>some smoe>some
sotry>story stil>still stll>still sutdent>student suer>sure srue>sure syas>says tkae>take taek>take
tehre>there thre>there htere>there theif>thief thsi>this tihs>this htis>this thees>these thoes>those
throught>through trhough>through togehter>together togther>together towrds>towards trys>tries
udnerstand>understand undrestand>understand understnad>understand veyr>very vrey>very wsa>was wass>was
watn>want wnated>wanted wnats>wants wanst>wants wahtever>whatever whatevr>whatever wehther>whether
wihle>while whiel>while wil>will wiil>will wirte>write wrtie>write wokr>work wrok>work wolrd>world
wrold>world worht>worth wrogn>wrong wront>wrong yaer>year yera>year yeras>years wating>waiting waitng>waiting
shamn>shaman shamna>shaman shamen>shaman paldin>paladin pladin>paladin palidn>paladin paladn>paladin
warlok>warlock warlcok>warlock warrir>warrior waror>warrior huntre>hunter rouge>rogue rouges>rogues mgae>mage
mgaes>mages preist>priest preists>priests druiid>druid evokr>evoker evoekr>evoker
persue>pursue persued>pursued guld>guild dungon>dungeon dungen>dungeon dungeoon>dungeon reall>really realyl>really
waht's>what's taht's>that's coudln't>couldn't shoudn't>shouldn't
]])

-- Contractions written without the apostrophe (bare form > right one). The bare form is never an English word of its
-- own here: ill, its, were, well, hell, shell, lets, id are, so they go through the word pairs instead. Rules.lua
-- adds SCOWL's contractions on top under the same condition.
ns.AUTOCORRECT_APOSTROPHES = Fixes([[
dont>don't cant>can't wont>won't im>I'm ive>I've youre>you're theyre>they're thats>that's whats>what's hes>he's
shes>she's didnt>didn't doesnt>doesn't isnt>isn't wasnt>wasn't arent>aren't werent>weren't havent>haven't
hasnt>hasn't hadnt>hadn't wouldnt>wouldn't couldnt>couldn't shouldnt>shouldn't mustnt>mustn't youll>you'll
youve>you've youd>you'd theyll>they'll theyve>they've theyd>they'd weve>we've wouldve>would've couldve>could've
shouldve>should've mightve>might've theres>there's wheres>where's whos>who's aint>ain't hows>how's whens>when's
itll>it'll thatll>that'll heres>here's
]])

-- Bare forms that are words of their own: never turned into a contraction on their own.
ns.AUTOCORRECT_NOT_CONTRACTIONS = Set("ill its were well hell shell lets id wed shed hed whore sha ma os")

-- Two-word fixes, matched on the last two words typed (lowercase): { first, { second = true }, fix1, fix2 }. A nil
-- fix leaves that word as typed.
-- Only words that can't follow the other reading ("an ill tank", "your next pull", "it lets all players").
local VERBS = Set([[be meet see go do get have try take make need come wait brb help check ask tell send bring buy
find give look join invite inv pass start stop leave never just probably still always keep show let call think
write pick grab]])
local IT_IS = Set([[been a an not the so ok okay fine just going time over all only really very too still already
on in up down done gone free cool fun good bad great late early true like about because definitely probably actually
almost pretty kinda worth easy hard weird broken bugged fixed here there me you him them us no never]])
local YOU_ARE = Set([[late welcome wrong not going so too the a an really still already just being doing getting
looking making playing sure kidding joking probably definitely gonna always never able supposed allowed crazy
insane here there]])
local LET_US = Set([[go do try see get start move wait pull kill head meet find just not be make take have run say
hope]])

ns.AUTOCORRECT_PAIRS = {
	{ "could", Set("of"), nil, "have" },
	{ "would", Set("of"), nil, "have" },
	{ "should", Set("of"), nil, "have" },
	{ "must", Set("of"), nil, "have" },
	{ "might", Set("of"), nil, "have" },
	{ "ill", VERBS, "I'll", nil },
	{ "its", IT_IS, "it's", nil },
	{ "your", YOU_ARE, "you're", nil },
	{ "lets", LET_US, "let's", nil },
}

-- Short everyday words that run into the next or previous one ("tothe", "infront", "doyou"): a run-together word is
-- only split when one half is one of these.
ns.AUTOCORRECT_SPLIT_WORDS = Set([[a i to of in on at is it be we me my he an as or so up no do go by the and for you
but not are was can get all any our out her his him she its who how why one off too may own]])
-- The ones that may be the second half: not "on", "in", "an", "at", "of", which end so many misspelled words
-- (dungon, collecton) that a split there would mostly be wrong.
ns.AUTOCORRECT_SPLIT_RIGHT = Set([[a i to it me my up is be we do go so the and you but not are was can all out
too]])

-- Real words no guess should land on: archaic or odd ones that sit one key away from everyday words (ther -> thee).
ns.AUTOCORRECT_NO_GUESS = Set([[thee thou thy thine ye hath doth tis twas ere nay oft whence thither hither wilt
shalt art]])

-- Doubled words that are fine ("bye bye"), by the word.
ns.AUTOCORRECT_DOUBLES_OK = Set([[had that bye ha very so no go really far many more now there well yes wait come
hey la blah knock boo chop too do run pew choo gg ty lol kk hip night tsk tut yeah yes oh please hello omg ok okay
nope sure woo yay]])

-- Chat shorthand, slang and dialect that is never touched (lowercase). Real words don't need to be here.
ns.AUTOCORRECT_SHORTHAND = Set([[
lol lmao lmfao rofl brb afk gg ggs gj ty tyvm thx thnx np pls plz plox omg omfg idk idc imo imho btw ok okk k kk gz
grats gratz wb gl hf glhf lfg lfm lf wts wtb wtt ilvl dps hps heals mats xp exp rep inc oom cc aoe dot dots hot
debuff nerf nerfed op goin nothin somethin doin gettin lookin comin u ur ya yah yeh yeah yep yup nope nah hmm hmmm
heh haha hehe hihi ugh nvm irl tbh ffs wtf tho cya gn gm sry mb boe bop boa ah rdy r y n m x xd ez pog poggers kekw
kek lul smh fml jk iirc afaik ikr ngl af asap atm bbl bbs bc cuz coz cos dc dcd fyi gtg g2g hbu hru ic ily jw lmk
nm nw ofc omw ppl prob probs rl rn sec srsly sup thanx tmrw tmr tn tnx tyty ttyl w wbu wyd yw yolo zomg xmog tmog
transmog alts toon toons pug pugs mythic heroic hc lfr bis dmg crit agi str int stam mob mobs wipe wiped aggro
taunt cd cds lust bl noob newb nub tryhard boost dk dh pally pala lock warr shammy sham evoker evo vdh bdk gonna
wanna gotta kinda sorta dunno lemme gimme outta lotta ain innit aye ye yer yall ima imma tryna bruh bro sis fam
dw ffa wq wqs ksm rio ilvls prot ret disc sub sin mm bm surv ele enh resto mw ww brm gief heya hai hiya
howdy okey okie mhm umm uhh ahh ooh welp congratz wp lolol heyy sadge copium hopium gamba poggies pog achi achis
achiev achievs achieves mplus whisp whisps guildy guildies pugger puggers pallys blizz specc specced huntard
sellin buyin wowhead raiderio rio wowaudit warcraftlogs wcl simc raidbots
]])

-- WoW words an English dictionary doesn't know, so they're never "fixed" (lowercase): game terms, races, classes,
-- professions, lore names. They're known words only, never a guess's answer. The client adds more at runtime
-- (Autocorrect.lua: class, race and map names; words other players use in chat).
ns.AUTOCORRECT_GAME_WORDS = Set([[
respec respecs addon addons keybind keybinds macro macros ui hp mana procs proc procced gcd melee oneshot oneshots
oneshotted brez rez rezz res bres battlerez bloodlust timewarp heroism lust cleave dispel dispels purge kick kicks
interrupt interrupts aoe aoes tanking healing healer healers dps'ing kiting aggro threat taunt taunts cooldown
cooldowns trinket trinkets enchant enchants enchanting gem gems gemmed socket sockets reforge transmog transmogs
mog mogs xmog appearance appearances toy toys pet pets battlepet battlepets mount mounts mounted dismount questline
questlines questgiver questgivers quester questing dailies daily weekly weeklies renown rep reps reputation vault
vaults delve delves delver keystone keystones affix affixes lockout lockouts raider raiders raiding mythic mythics
heroics normals lfr lfd lfg queue queued queues requeue summon summons summoned portal portals hearth hearthstone
hearthed flightpath flightpaths fp griffon gryphon gryphons wyvern wyverns taxi zeppelin zeppelins tram respawn
respawns respawned spawn spawns spawned despawn despawned ninja ninjaed ninjaing pvp pve rbg rbgs bg bgs arena
arenas rated unrated honor conquest valor crest crests flightstone anima azerite artifact legendaries legendary
conduit conduits soulbind soulbinds covenant covenants talent talents spec specs specced herbalism herbalist
skinning skinner jewelcrafting jewelcrafter jc inscription scribe alchemy alchemist engineering engineer tailoring
tailor leatherworking leatherworker lw blacksmithing blacksmith bs mining miner fishing cooking archaeology
lockpicking pickpocket pickpocketing crafter crafters crafting reagent reagents mats vendor vendors vendored
npc npcs mob mobs elite elites rare rares worldboss worldbosses boss bosses miniboss trash wipe wipes wiped
pulls pulled puller deathknight deathknights paladin paladins pally pallies warlock warlocks lock locks shaman
shamans druid druids monk monks evoker evokers demonhunter demonhunters priest priests mage mages rogue rogues
hunter hunters warrior warriors tauren taurens orc orcs troll trolls goblin goblins undead forsaken bloodelf
bloodelves belf belfs draenei draeneis worgen worgens pandaren gnome gnomes dwarf dwarves nelf nelfs nightelf
nightelves human humans vulpera nightborne nightbornes highmountain lightforged voidelf voidelves zandalari
kultiran kultirans mechagnome mechagnomes maghar darkiron dracthyr earthen haranir murloc murlocs kobold kobolds
gnoll gnolls furbolg furbolgs harpy harpies centaur centaurs naga nagas makrura quilboar trogg troggs ogre ogres
arakkoa tuskarr tuskarrs dragonkin drakonid drakonids nerubian nerubians kaldorei quel'dorei sin'dorei shal'dorei
thrall jaina sylvanas arthas illidan voljin vol'jin garrosh anduin varian wrathion alexstrasza nozdormu ysera
deathwing ragnaros nefarian onyxia kel'thuzad lich lichking tyrande malfurion velen khadgar medivh gul'dan guldan
kil'jaeden kiljaeden archimonde sargeras xal'atath xalatath alleria turalyon baine thalyssra lor'themar lorthemar
rexxar chromie tirion uther gallywix magni moira genn greymane talanji zekhan dagran faerin arathor azshara
n'zoth nzoth yogg c'thun cthun denathrius zovaal kael kael'thas kaelthas vashj maiev akama brann bronzebeard
tyr alleria khadgar archon archons catalyst catalysted catalysting nerubar ansurek locus walker
dragonflight midnight shadowlands bfa wotlk tbc cata mop wod legion vanilla classic hardcore sod expac expacs
expansion expansions prepatch patch patches nerf nerfs nerfed buff buffs buffed debuff debuffs hotfix hotfixes
ilvl itemlevel bis boe boes bop boa warbound warband warbands alt alts altoholic toon toons main mains guildie
guildies guildmate guildmates officer officers gm gms realm realms crossrealm sharding layer layering
afk'ing dc'd ty'd gz'd lol'd
]])

-- Place names written with their capitals: cities, districts and zones across Azeroth and beyond. Single words become
-- a name fix only when their lowercase form isn't an English word (Rules.lua); two-word names go through the word
-- pairs (Line.lua). The client's own map names are added at runtime (Autocorrect.lua).
ns.AUTOCORRECT_PLACES = {
	"Stormwind", "Old Town", "Trade District", "Mage Quarter", "Dwarven District", "Cathedral Square",
	"Orgrimmar", "Ironforge", "Darnassus", "Undercity", "Thunder Bluff", "Silvermoon", "Exodar", "Shattrath",
	"Dalaran", "Booty Bay", "Gadgetzan", "Ratchet", "Everlook", "Valdrakken", "Dornogal", "Oribos", "Boralus",
	"Zuldazar", "Mechagon", "Nazjatar", "Elwynn Forest", "Elwynn", "Westfall", "Redridge", "Duskwood",
	"Stranglethorn", "Durotar", "Mulgore", "Barrens", "Ashenvale", "Tanaris", "Winterspring", "Felwood", "Feralas",
	"Desolace", "Silithus", "Teldrassil", "Darkshore", "Azshara", "Hinterlands", "Tirisfal", "Silverpine",
	"Hillsbrad", "Arathi", "Dun Morogh", "Loch Modan", "Searing Gorge", "Burning Steppes", "Blasted Lands",
	"Deadwind Pass", "Thousand Needles", "Stonetalon", "Dustwallow", "Moonglade", "Hellfire", "Zangarmarsh",
	"Nagrand", "Terokkar", "Netherstorm", "Shadowmoon", "Northrend", "Icecrown", "Dragonblight", "Sholazar",
	"Storm Peaks", "Grizzly Hills", "Howling Fjord", "Borean Tundra", "Wintergrasp", "Deepholm", "Uldum", "Hyjal",
	"Pandaria", "Jade Forest", "Townlong", "Draenor", "Gorgrond", "Talador", "Tanaan", "Ashran", "Broken Isles",
	"Suramar", "Highmountain", "Stormheim", "Azsuna", "Argus", "Kul Tiras", "Zandalar", "Drustvar", "Tiragarde",
	"Stormsong", "Nazmir", "Shadowlands", "Maldraxxus", "Ardenweald", "Revendreth", "Korthia", "Zereth Mortis",
	"Dragon Isles", "Waking Shores", "Azure Span", "Thaldraszus", "Zaralek", "Emerald Dream", "Khaz Algar",
	"Isle of Dorn", "Ringing Deeps", "Hallowfall", "Undermine", "Karesh", "Eversong", "Harandar", "Voidstorm",
	"Azeroth", "Kalimdor", "Outland", "Karazhan", "Naxxramas", "Ulduar", "Molten Core", "Blackrock",
	"Blackwing Lair", "Onyxia", "Deadmines", "Stockades", "Scholomance", "Stratholme", "Uldaman", "Maraudon",
	"Gnomeregan", "Wailing Caverns", "Shadowfang", "Scarlet Monastery", "Dire Maul", "Sunwell", "Goldshire",
	"Lakeshire", "Darkshire", "Sentinel Hill", "Crossroads", "Southshore", "Tarren Mill", "Menethil", "Thelsamar",
	"Kharanos", "Razor Hill", "Astranaar", "Auberdine", "Theramore", "Feathermoon", "Aerie Peak", "Hammerfall",
	"Kargath", "Steamwheedle",
}

-- QWERTY rows: a typo that hits the key next to the right one is a likelier slip than a far one.
ns.AUTOCORRECT_KEYS = List("qwertyuiop asdfghjkl zxcvbnm")
