	////////////
	//SECURITY//
	////////////
#define TOPIC_SPAM_DELAY	2		//2 ticks is about 2/10ths of a second; it was 4 ticks, but that caused too many clicks to be lost due to lag
#define UPLOAD_LIMIT		10485760	//Restricts client uploads to the server to 10MB //Boosted this thing. What's the worst that can happen?
#define MIN_CLIENT_VERSION	0		//Just an ambiguously low version for now, I don't want to suddenly stop people playing.
									//I would just like the code ready should it ever need to be used.
	/*
	When somebody clicks a link in game, this Topic is called first.
	It does the stuff in this proc and  then is redirected to the Topic() proc for the src=[0xWhatever]
	(if specified in the link). ie locate(hsrc).Topic()

	Such links can be spoofed.

	Because of this certain things MUST be considered whenever adding a Topic() for something:
		- Can it be fed harmful values which could cause runtimes?
		- Is the Topic call an admin-only thing?
		- If so, does it have checks to see if the person who called it (usr.client) is an admin?
		- Are the processes being called by Topic() particularly laggy?
		- If so, is there any protection against somebody spam-clicking a link?
	If you have any  questions about this stuff feel free to ask. ~Carn
	*/
/client
	var/account_joined = ""
	var/account_age

/client/Topic(href, href_list, hsrc)
	//var/timestart = world.timeofday
	//testing("topic call for [usr] [href]")
	if(!usr || usr != mob)	//stops us calling Topic for somebody else's client. Also helps prevent usr=null
		return

	//Reduces spamming of links by dropping calls that happen during the delay period
//	if(next_allowed_topic_time > world.time)
//		return
	//next_allowed_topic_time = world.time + TOPIC_SPAM_DELAY

	//search the href for script injection
	if( findtext(href,"<script",1,0) )
		world.log << "Attempted use of scripts within a topic call, by [src]"
		message_admins("Attempted use of scripts within a topic call, by [src]")
		//del(usr)
		return

	//Admin PM
	if(href_list["priv_msg"])
		var/client/C = locate(href_list["priv_msg"])
		if(ismob(C)) 		//Old stuff can feed-in mobs instead of clients
			var/mob/M = C
			C = M.client
		cmd_admin_pm(C,null)
		return

	//Logs all hrefs
	if(config && config.log_hrefs && investigations[I_HREFS])
		var/datum/log_controller/I = investigations[I_HREFS]
		I.write("<small>[time2text(world.timeofday,"hh:mm")] [src] (usr:[usr])</small> || [hsrc ? "[hsrc] " : ""][href]<br />")

	switch(href_list["_src_"])
		if("holder")	hsrc = holder
		if("usr")		hsrc = mob
		if("prefs")		return prefs.process_link(usr,href_list)
		if("vars")		return view_var_Topic(href,href_list,hsrc)

	..()	//redirect to hsrc.Topic()
	//testing("[usr] topic call took [(world.timeofday - timestart)/10] seconds")

/client/proc/handle_spam_prevention(var/message, var/mute_type)
	if(config.automute_on && !holder && src.last_message == message)
		src.last_message_count++
		if(src.last_message_count >= SPAM_TRIGGER_AUTOMUTE)
			src << "<span class='warning'>You have exceeded the spam filter limit for identical messages. An auto-mute was applied.</span>"
			cmd_admin_mute(src.mob, mute_type, 1)
			return 1
		if(src.last_message_count >= SPAM_TRIGGER_WARNING)
			src << "<span class='warning'>You are nearing the spam filter limit for identical messages.</span>"
			return 0
	else
		last_message = message
		src.last_message_count = 0
		return 0

//This stops files larger than UPLOAD_LIMIT being sent from client to server via input(), client.Import() etc.
/client/AllowUpload(filename, filelength)
	if(filelength > UPLOAD_LIMIT)
		src << "<font color='red'>Error: AllowUpload(): File Upload too large. Upload Limit: [UPLOAD_LIMIT/1024]KiB.</font>"
		return 0
/*	//Don't need this at the moment. But it's here if it's needed later.
	//Helps prevent multiple files being uploaded at once. Or right after eachother.
	var/time_to_wait = fileaccess_timer - world.time
	if(time_to_wait > 0)
		src << "<font color='red'>Error: AllowUpload(): Spam prevention. Please wait [round(time_to_wait/10)] seconds.</font>"
		return 0
	fileaccess_timer = world.time + FTPDELAY	*/
	return 1


	///////////
	//CONNECT//
	///////////
/client/New(TopicData)
	if(config)
		winset(src, null, "outputwindow.output.style=[config.world_style_config];")
		winset(src, null, "window1.msay_output.style=[config.world_style_config];") // it isn't possible to set two window elements in the same winset so we need to call it for each element we're assigning a stylesheet.
	else
		src << "<span class='warning'>The stylesheet wasn't properly setup call an administrator to reload the stylesheet or relog.</span>"
	TopicData = null							//Prevent calls to client.Topic from connect

	//Admin Authorisation
	holder = admin_datums[ckey]
	if(holder)
		admins += src
		holder.owner = src

	if(connection != "seeker")					//Invalid connection type.
		return null
	if(byond_version < MIN_CLIENT_VERSION)		//Out of date client.
		return null

	if(IsGuestKey(key))
		alert(src,"This server doesn't allow guest accounts to play. Please go to http://www.byond.com/ and register for a key.","Guest","OK")
		del(src)
		return

	// Change the way they should download resources.
	if(config.resource_urls)
		src.preload_rsc = pick(config.resource_urls)
	else src.preload_rsc = 1 // If config.resource_urls is not set, preload like normal.

	src << "<span class='warning'>If the title screen is black, resources are still downloading. Please be patient until the title screen appears.</span>"

	clients += src
	directory[ckey] = src


	//preferences datum - also holds some persistant data for the client (because we may as well keep these datums to a minimum)
	prefs = preferences_datums[ckey]
	if(!prefs)
		prefs = new /datum/preferences(src)
		preferences_datums[ckey] = prefs
	prefs.last_ip = address				//these are gonna be used for banning
	prefs.last_id = computer_id			//these are gonna be used for banning

	. = ..()	//calls mob.Login()

	if(custom_event_msg && custom_event_msg != "")
		src << "<h1 class='alert'>Custom Event</h1>"
		src << "<h2 class='alert'>A custom event is taking place. OOC Info:</h2>"
		src << "<span class='alert'>[html_encode(custom_event_msg)]</span>"
		src << "<br>"

	if( (world.address == address || !address) && !host )
		host = key
		world.update_status()

	if(holder)
		add_admin_verbs()
		admin_memo_show()

	log_client_to_db()

	send_resources()

	if(prefs.lastchangelog != changelog_hash) //bolds the changelog button on the interface so we know there are updates.
		winset(src, "rpane.changelog", "background-color=#eaeaea;font-style=bold")
		prefs.SetChangelog(ckey,changelog_hash)
		src << "<span class='info'>Changelog has changed since your last visit.</span>"

	//Set map label to correct map name
	winset(src, "rpane.map", "text=\"[map.nameLong]\"")

	// Notify scanners.
	INVOKE_EVENT(on_login,list(
		"client"=src,
		"admin"=(holder!=null)
	))

	//////////////
	//DISCONNECT//
	//////////////
/client/Del()
	if(holder)
		holder.owner = null
		admins -= src
	directory -= ckey
	clients -= src
	return ..()

/client/proc/log_client_to_db()
	if(IsGuestKey(key))
		return

	establish_db_connection()

	if(!dbcon.IsConnected())
		return
	var/list/http[] = world.Export("http://www.byond.com/members/[src.key]?format=text")  // Retrieve information from BYOND
	var/Joined = 2550-01-01
	if(http && http.len && ("CONTENT" in http))
		var/String = file2text(http["CONTENT"])  //  Convert the HTML file to text
		var/JoinPos = findtext(String, "joined")+10  //  Parse for the joined date
		Joined = copytext(String, JoinPos, JoinPos+10)  //  Get the date in the YYYY-MM-DD format

	account_joined = Joined

	var/sql_ckey = sanitizeSQL(ckey)
	var/age
	testing("sql_ckey = [sql_ckey]")
	var/DBQuery/query = dbcon.NewQuery("SELECT id, datediff(Now(),firstseen) as age, datediff(Now(),accountjoined) as age2 FROM erro_player WHERE ckey = '[sql_ckey]'")
	query.Execute()
	var/sql_id = 0
	while(query.NextRow())
		sql_id = query.item[1]
		player_age = text2num(query.item[2])
		age = text2num(query.item[3])
		break

	var/sql_address = sanitizeSQL(address)

	var/DBQuery/query_ip = dbcon.NewQuery("SELECT ckey FROM erro_player WHERE ip = '[sql_address]'")
	query_ip.Execute()
	related_accounts_ip = ""
	while(query_ip.NextRow())
		related_accounts_ip += "[query_ip.item[1]], "


	var/sql_computerid = sanitizeSQL(computer_id)

	var/DBQuery/query_cid = dbcon.NewQuery("SELECT ckey FROM erro_player WHERE computerid = '[sql_computerid]'")
	query_cid.Execute()
	related_accounts_cid = ""
	while(query_cid.NextRow())
		related_accounts_cid += "[query_cid.item[1]], "

	//Just the standard check to see if it's actually a number
	if(sql_id)
		if(istext(sql_id))
			sql_id = text2num(sql_id)
		if(!isnum(sql_id))
			return
	//else
		//var/url = pick("byond://ss13.nexisonline.net:1336", "byond://ss13.nexisonline.net:1336", "byond://ss13.nexisonline.net:1336", "byond://ss13.nexisonline.net:1336")
		//src << link(url)

		//var/Server/s = random_server_list[key]
		//world.log << "Sending [src.key] to random server: [url]"
		//src << link(s.url)
		//del(src)

	var/admin_rank = "Player"

	if(istype(holder))
		admin_rank = holder.rank

	var/sql_admin_rank = sanitizeSQL(admin_rank)

	if(sql_id)
		//Player already identified previously, we need to just update the 'lastseen', 'ip' and 'computer_id' variables
		var/DBQuery/query_update
		if(isnum(age))
			query_update = dbcon.NewQuery("UPDATE erro_player SET lastseen = Now(), ip = '[sql_address]', computerid = '[sql_computerid]', lastadminrank = '[sql_admin_rank]' WHERE id = [sql_id]")
		else
			query_update = dbcon.NewQuery("UPDATE erro_player SET lastseen = Now(), ip = '[sql_address]', computerid = '[sql_computerid]', lastadminrank = '[sql_admin_rank]', accountjoined = '[Joined]' WHERE id = [sql_id]")
		query_update.Execute()
	else
		//New player!! Need to insert all the stuff
		var/DBQuery/query_insert = dbcon.NewQuery("INSERT INTO erro_player (id, ckey, firstseen, lastseen, ip, computerid, lastadminrank, accountjoined) VALUES (null, '[sql_ckey]', Now(), Now(), '[sql_address]', '[sql_computerid]', '[sql_admin_rank]', '[Joined]')")
		query_insert.Execute()

	if(!isnum(age))
		var/DBQuery/query_age = dbcon.NewQuery("SELECT datediff(Now(),accountjoined) as age2 FROM erro_player WHERE ckey = '[sql_ckey]'")
		query_age.Execute()
		while(query_age.NextRow())
			age = text2num(query_age.item[1])
	if(age < 14)
		message_admins("[ckey(key)]/([src]) is a relatively new player, may consider watching them. AGE = [age]  First seen = [player_age]")
		log_admin(("[ckey(key)]/([src]) is a relatively new player, may consider watching them. AGE = [age] First seen = [player_age]"))
	testing("[src]/[ckey(key)] logged in with age of [age]/[player_age]/[Joined]")
	account_age = age

	// logging player access
	var/server_address_port = "[world.internet_address]:[world.port]"
	var/sql_server_address_port = sanitizeSQL(server_address_port)
	var/DBQuery/query_connection_log = dbcon.NewQuery("INSERT INTO `erro_connection_log`(`id`,`datetime`,`serverip`,`ckey`,`ip`,`computerid`) VALUES(null,Now(),'[sql_server_address_port]','[sql_ckey]','[sql_address]','[sql_computerid]');")

	query_connection_log.Execute()


#undef TOPIC_SPAM_DELAY
#undef UPLOAD_LIMIT
#undef MIN_CLIENT_VERSION

//checks if a client is afk
//3000 frames = 5 minutes
/client/proc/is_afk(duration=3000)
	if(inactivity > duration)	return inactivity
	return 0

/client/verb/resend_resources()
	set name = "Resend Resources"
	set desc = "Re-send resources for NanoUI. May help those with NanoUI issues."
	set category = "Preferences"

	usr << "<span class='notice'>Re-sending NanoUI resources.  This may result in lag.</span>"
	nanomanager.send_resources(src)

//send resources to the client. It's here in its own proc so we can move it around easiliy if need be
/client/proc/send_resources()
//	preload_vox() //Causes long delays with initial start window and subsequent windows when first logged in.

	spawn
		// Preload the HTML interface. This needs to be done due to BYOND bug http://www.byond.com/forum/?post=1487244 (hidden issue)
		// "browse_rsc() sometimes failed when an attempt was made to check on the status of a the file before it had finished downloading. This problem appeared only in threaded mode."
		var/datum/html_interface/hi
		for (var/type in typesof(/datum/html_interface))
			hi = new type(null)
			hi.sendResources(src)

	// Send NanoUI resources to this client
	spawn nanomanager.send_resources(src)

	getFiles(
		'html/search.js',
		'html/panels.css',
		'icons/pda_icons/pda_atmos.png',
		'icons/pda_icons/pda_back.png',
		'icons/pda_icons/pda_bell.png',
		'icons/pda_icons/pda_blank.png',
		'icons/pda_icons/pda_boom.png',
		'icons/pda_icons/pda_bucket.png',
		'icons/pda_icons/pda_crate.png',
		'icons/pda_icons/pda_cuffs.png',
		'icons/pda_icons/pda_eject.png',
		'icons/pda_icons/pda_exit.png',
		'icons/pda_icons/pda_flashlight.png',
		'icons/pda_icons/pda_honk.png',
		'icons/pda_icons/pda_mail.png',
		'icons/pda_icons/pda_medical.png',
		'icons/pda_icons/pda_menu.png',
		'icons/pda_icons/pda_mule.png',
		'icons/pda_icons/pda_notes.png',
		'icons/pda_icons/pda_power.png',
		'icons/pda_icons/pda_alert.png',
		'icons/pda_icons/pda_rdoor.png',
		'icons/pda_icons/pda_reagent.png',
		'icons/pda_icons/pda_refresh.png',
		'icons/pda_icons/pda_scanner.png',
		'icons/pda_icons/pda_signaler.png',
		'icons/pda_icons/pda_status.png',
		'icons/pda_icons/pda_clock.png',
		'icons/pda_icons/pda_game.png',
		'icons/pda_icons/pda_egg.png',
		'icons/pda_icons/pda_minimap_box.png',
		'icons/pda_icons/pda_minimap_bg_notfound.png',
		'icons/pda_icons/pda_minimap_deff.png',
		'icons/pda_icons/pda_minimap_taxi.png',
		'icons/pda_icons/pda_minimap_meta.png',
		'icons/pda_icons/pda_minimap_loc.gif',
		'icons/pda_icons/pda_minimap_mkr.gif',
		'icons/pda_icons/snake_icons/snake_background.png',
		'icons/pda_icons/snake_icons/snake_highscore.png',
		'icons/pda_icons/snake_icons/snake_newgame.png',
		'icons/pda_icons/snake_icons/snake_station.png',
		'icons/pda_icons/snake_icons/snake_pause.png',
		'icons/pda_icons/snake_icons/snake_maze1.png',
		'icons/pda_icons/snake_icons/snake_maze2.png',
		'icons/pda_icons/snake_icons/snake_maze3.png',
		'icons/pda_icons/snake_icons/snake_maze4.png',
		'icons/pda_icons/snake_icons/snake_maze5.png',
		'icons/pda_icons/snake_icons/snake_maze6.png',
		'icons/pda_icons/snake_icons/snake_maze7.png',
		'icons/pda_icons/snake_icons/arrows/pda_snake_arrow_north.png',
		'icons/pda_icons/snake_icons/arrows/pda_snake_arrow_east.png',
		'icons/pda_icons/snake_icons/arrows/pda_snake_arrow_west.png',
		'icons/pda_icons/snake_icons/arrows/pda_snake_arrow_south.png',
		'icons/pda_icons/snake_icons/numbers/snake_0.png',
		'icons/pda_icons/snake_icons/numbers/snake_1.png',
		'icons/pda_icons/snake_icons/numbers/snake_2.png',
		'icons/pda_icons/snake_icons/numbers/snake_3.png',
		'icons/pda_icons/snake_icons/numbers/snake_4.png',
		'icons/pda_icons/snake_icons/numbers/snake_5.png',
		'icons/pda_icons/snake_icons/numbers/snake_6.png',
		'icons/pda_icons/snake_icons/numbers/snake_7.png',
		'icons/pda_icons/snake_icons/numbers/snake_8.png',
		'icons/pda_icons/snake_icons/numbers/snake_9.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_body_east.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_body_east_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_body_west.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_body_west_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_body_north.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_body_north_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_body_south.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_body_south_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_eastnorth.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_eastnorth_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_eastsouth.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_eastsouth_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_westnorth.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_westnorth_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_westsouth.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_westsouth_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_eastnorth2.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_eastnorth2_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_eastsouth2.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_eastsouth2_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_westnorth2.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_westnorth2_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_westsouth2.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodycorner_westsouth2_full.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodytail_east.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodytail_north.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodytail_south.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bodytail_west.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bonus1.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bonus2.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bonus3.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bonus4.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bonus5.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_bonus6.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_egg.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_head_east.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_head_east_open.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_head_west.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_head_west_open.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_head_north.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_head_north_open.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_head_south.png',
		'icons/pda_icons/snake_icons/elements/pda_snake_head_south_open.png',
		'icons/pda_icons/snake_icons/volume/snake_volume0.png',
		'icons/pda_icons/snake_icons/volume/snake_volume1.png',
		'icons/pda_icons/snake_icons/volume/snake_volume2.png',
		'icons/pda_icons/snake_icons/volume/snake_volume3.png',
		'icons/pda_icons/snake_icons/volume/snake_volume4.png',
		'icons/pda_icons/snake_icons/volume/snake_volume5.png',
		'icons/pda_icons/snake_icons/volume/snake_volume6.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_0.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_1.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_2.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_3.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_4.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_5.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_6.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_7.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_8.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_counter_9.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_1.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_1_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_2.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_2_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_3.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_3_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_4.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_4_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_5.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_5_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_6.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_6_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_7.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_7_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_8.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_8_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_empty.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_empty_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_full.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_full_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_question.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_question_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_flag.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_flag_selected.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_mine_unsplode.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_mine_splode.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_tile_mine_wrong.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_frame_counter.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_frame_smiley.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_border_bot.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_border_top.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_border_right.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_border_left.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_border_cornertopleft.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_border_cornertopright.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_border_cornerbotleft.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_border_cornerbotright.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_bg_beginner.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_bg_intermediate.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_bg_expert.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_bg_custom.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_flag.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_question.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_settings.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_smiley_normal.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_smiley_press.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_smiley_fear.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_smiley_dead.png',
		'icons/pda_icons/minesweeper_icons/minesweeper_smiley_win.png',
		'icons/pda_icons/spesspets_icons/spesspets_bg.png',
		'icons/pda_icons/spesspets_icons/spesspets_egg0.png',
		'icons/pda_icons/spesspets_icons/spesspets_egg1.png',
		'icons/pda_icons/spesspets_icons/spesspets_egg2.png',
		'icons/pda_icons/spesspets_icons/spesspets_egg3.png',
		'icons/pda_icons/spesspets_icons/spesspets_hatch.png',
		'icons/pda_icons/spesspets_icons/spesspets_talk.png',
		'icons/pda_icons/spesspets_icons/spesspets_walk.png',
		'icons/pda_icons/spesspets_icons/spesspets_feed.png',
		'icons/pda_icons/spesspets_icons/spesspets_clean.png',
		'icons/pda_icons/spesspets_icons/spesspets_heal.png',
		'icons/pda_icons/spesspets_icons/spesspets_fight.png',
		'icons/pda_icons/spesspets_icons/spesspets_visit.png',
		'icons/pda_icons/spesspets_icons/spesspets_work.png',
		'icons/pda_icons/spesspets_icons/spesspets_cash.png',
		'icons/pda_icons/spesspets_icons/spesspets_rate.png',
		'icons/pda_icons/spesspets_icons/spesspets_Corgegg.png',
		'icons/pda_icons/spesspets_icons/spesspets_Chimpegg.png',
		'icons/pda_icons/spesspets_icons/spesspets_Borgegg.png',
		'icons/pda_icons/spesspets_icons/spesspets_Syndegg.png',
		'icons/pda_icons/spesspets_icons/spesspets_hunger.png',
		'icons/pda_icons/spesspets_icons/spesspets_dirty.png',
		'icons/pda_icons/spesspets_icons/spesspets_hurt.png',
		'icons/pda_icons/spesspets_icons/spesspets_mine.png',
		'icons/pda_icons/spesspets_icons/spesspets_sleep.png',
		'icons/spideros_icons/sos_1.png',
		'icons/spideros_icons/sos_2.png',
		'icons/spideros_icons/sos_3.png',
		'icons/spideros_icons/sos_4.png',
		'icons/spideros_icons/sos_5.png',
		'icons/spideros_icons/sos_6.png',
		'icons/spideros_icons/sos_7.png',
		'icons/spideros_icons/sos_8.png',
		'icons/spideros_icons/sos_9.png',
		'icons/spideros_icons/sos_10.png',
		'icons/spideros_icons/sos_11.png',
		'icons/spideros_icons/sos_12.png',
		'icons/spideros_icons/sos_13.png',
		'icons/spideros_icons/sos_14.png',
		'icons/xenoarch_icons/chart1.jpg',
		'icons/xenoarch_icons/chart2.jpg',
		'icons/xenoarch_icons/chart3.jpg',
		'icons/xenoarch_icons/chart4.jpg'
		)


/proc/get_role_desire_str(var/rolepref)
	switch(rolepref & ROLEPREF_VALMASK)
		if(ROLEPREF_NEVER)
			return "Never"
		if(ROLEPREF_NO)
			return "No"
		if(ROLEPREF_YES)
			return "Yes"
		if(ROLEPREF_ALWAYS)
			return "Always"
	return "???"

/client/proc/desires_role(var/role_id, var/display_to_user=0)
	var/role_desired = prefs.roles[role_id]
	if(display_to_user && !(role_desired & ROLEPREF_PERSIST))
		if(!(role_desired & ROLEPREF_POLLED))
			spawn
				var/answer = alert(src,"[role_id]\n\nNOTE:  You will only be polled about this role once per round. To change your choice, use Preferences > Setup Special Roles.  The change will take place AFTER this recruiting period.","Role Recruitment", "Yes","No","Never")
				switch(answer)
					if("Never")
						prefs.roles[role_id] = ROLEPREF_NEVER
					if("No")
						prefs.roles[role_id] = ROLEPREF_NO
					if("Yes")
						prefs.roles[role_id] = ROLEPREF_YES
					//if("Always")
					//	prefs.roles[role_id] = ROLEPREF_ALWAYS
				//testing("Client [src] answered [answer] to [role_id] poll.")
				prefs.roles[role_id] |= ROLEPREF_POLLED
		else
			src << "<span style='recruit'>The game is currently looking for [role_id] candidates.  Your current answer is <a href='?src=\ref[prefs]&preference=set_role&role_id=[role_id]'>[get_role_desire_str(role_desired)]</a>.</span>"
	return role_desired & ROLEPREF_ENABLE