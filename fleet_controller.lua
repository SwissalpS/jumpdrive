
local update_formspec = function(meta, pos)

	local active = meta:get_int("active")

	local button_line =
		"button_exit[0,2;2,1;jump;Jump]" ..
		"button_exit[2,2;2,1;show;Show]" ..
		"button_exit[4,2;2,1;save;Save]" ..
		"button[6,2;2,1;reset;Reset]"

	if active == 1 then
		local jump_index = meta:get_int("jump_index")
		local jump_list = minetest.deserialize( meta:get_string("jump_list") )

		meta:set_string("infotext", "Controller active: " .. jump_index .. "/" .. #jump_list)

		local button_line = "button_exit[0,2;8,1;stop;Stop]"
	else
		meta:set_string("infotext", "Ready")
	end

	meta:set_string("formspec", "size[8,10;]" ..
		"field[0,1;2,1;x;X;" .. meta:get_int("x") .. "]" ..
		"field[3,1;2,1;y;Y;" .. meta:get_int("y") .. "]" ..
		"field[6,1;2,1;z;Z;" .. meta:get_int("z") .. "]" ..

		button_line ..

		"list[context;main;0,3;8,1;]" ..

		"button[0,4;4,1;write_book;Write to book]" ..
		"button[4,4;4,1;read_book;Read from book]" ..

		"list[current_player;main;0,5;8,4;]" ..

		-- listring stuff
		"listring[]")
end

minetest.register_node("jumpdrive:fleet_controller", {
	description = "Jumpdrive Fleet controller",

	tiles = {"jumpdrive_fleet_controller.png"},
	groups = {cracky=3,oddly_breakable_by_hand=3},
	sounds = default.node_sound_glass_defaults(),

	light_source = 13,

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_int("x", pos.x)
		meta:set_int("y", pos.y)
		meta:set_int("z", pos.z)

		-- jumping active (1=active)
		meta:set_int("active", 0)
		-- if active, current index in jump list (1...n)
		meta:set_int("jump_index", 0)
		-- jump list
		meta:set_string("jump_list", "")

		local inv = meta:get_inventory()
		inv:set_size("main", 8)

		update_formspec(meta, pos)
	end,

	can_dig = function(pos,player)
		local meta = minetest.get_meta(pos);
		local inv = meta:get_inventory()
		local name = player:get_player_name()

		return inv:is_empty("main") and not minetest.is_protected(pos, name)
	end,

	on_receive_fields = function(pos, formname, fields, sender)

		local meta = minetest.get_meta(pos);

		if not sender then
			return
		end

		if minetest.is_protected(pos, sender:get_player_name()) then
			-- not allowed
			return
		end

		if fields.read_book then
			jumpdrive.read_from_book(pos)
			update_formspec(meta, pos)
			return
		end

		if fields.reset then
			jumpdrive.reset_coordinates(pos)
			update_formspec(meta, pos)
			return
		end

		if fields.write_book then
			jumpdrive.write_to_book(pos, sender)
			return
		end

		local x = tonumber(fields.x);
		local y = tonumber(fields.y);
		local z = tonumber(fields.z);

		if x == nil or y == nil or z == nil then
			return
		end

		-- update coords
		meta:set_int("x", x)
		meta:set_int("y", y)
		meta:set_int("z", z)
		update_formspec(meta, pos)

		local t0 = minetest.get_us_time()
		local engines_pos_list = jumpdrive.fleet.find_engines(pos)
		local t1 = minetest.get_us_time()
		minetest.log("action", "[jumpdrive-fleet] backbone traversing took " .. (t1 - t0) .. " us @ " .. minetest.pos_to_string(pos))

		local targetPos = {x=meta:get_int("x"),y=meta:get_int("y"),z=meta:get_int("z")}

		-- sort by distance, farthes first
		jumpdrive.fleet.sort_engines(pos, engines_pos_list)

		-- apply new coordinates
		jumpdrive.fleet.apply_coordinates(pos, targetPos, engines_pos_list)

		if fields.jump then
			--TODO check overlapping engines/radius
			meta:set_int("active", 1)
			meta:set_int("jump_index", 1)
			meta:set_string("jump_list", minetest.serialize(engines_pos_list))
			update_formspec(meta, pos)
		end

		if fields.stop then
			meta:set_int("active", 0)
			update_formspec(meta, pos)
		end

		if fields.show then
			minetest.chat_send_player(sender:get_player_name(), "Found " .. #engines_pos_list .. " jumpdrives")
			for _,engine_pos in pairs(engines_pos_list) do
				local success, msg = jumpdrive.simulate_jump(engine_pos, sender, true)
				if not success then
					minetest.chat_send_player(sender:get_player_name(), msg .. " @ " .. minetest.pos_to_string(engine_pos))
					return
				end
			end
			minetest.chat_send_player(sender:get_player_name(), "Simulation successful")
		end
		
	end,
})

-- fleet jump every n seconds
minetest.register_abm({
        label = "Jumpdrive fleet controller",
	nodenames = {"jumpdrive:fleet_controller"},
	interval = 2,
	chance = 1,
	action = function(pos)
		local meta = minetest.get_meta(pos)
		local active = meta:get_int("active")

		if active == 1 then
			local jump_index = meta:get_int("jump_index")
			local jump_list = minetest.deserialize( meta:get_string("jump_list") )

			if jump_list and jump_index and #jump_list >= jump_index then
				local node_pos = jump_list[jump_index]
				local success, msg = jumpdrive.execute_jump(node_pos)

				if success then
					-- at this point if it is the last engine the metadata does not exist anymore in the current location
					meta:set_int("jump_index", jump_index+1)
					update_formspec(meta, pos)
				else
					meta:set_string("infotext", "Engine (".. minetest.pos_to_string(node_pos) .. ") failed with: " .. msg)
					meta:set_int("active", 0)
				end

			else
				meta:set_int("active", 0)
			end
		end
	end
})

minetest.register_craft({
	output = 'jumpdrive:fleet_controller',
	recipe = {
		{'jumpdrive:engine', 'default:steelblock', 'jumpdrive:engine'},
		{'default:steelblock', 'default:steelblock', 'default:steelblock'},
		{'jumpdrive:engine', 'default:steelblock', 'jumpdrive:engine'}
	}
})