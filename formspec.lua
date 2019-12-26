local has_technic = minetest.get_modpath("technic")

local inv_offset = 0
if has_technic then
	inv_offset = 1.25
end

jumpdrive.update_formspec = function(meta, pos)
	local formspec =
		"size[8," .. 9.3+inv_offset .. ";]" ..

		"field[0.3,0.5;2,1;x;X;" .. meta:get_int("x") .. "]" ..
		"field[2.3,0.5;2,1;y;Y;" .. meta:get_int("y") .. "]" ..
		"field[4.3,0.5;2,1;z;Z;" .. meta:get_int("z") .. "]" ..
		"field[6.3,0.5;2,1;radius;Radius;" .. meta:get_int("radius") .. "]" ..

		"button_exit[0,1.5;2,1;jump;Jump]" ..
		"button_exit[2,1.5;2,1;show;Show]" ..
		"button_exit[4,1.5;2,1;save;Save]" ..
		"button[6,1.5;2,1;reset;Reset]" ..

		"button[0,2.5;4,1;write_book;Write to book]" ..
		"button[4,2.5;4,1;read_book;Read from book]" ..

		-- main inventory for fuel and books
		"list[context;main;0,3.75;8,1;]" ..

		-- player inventory
		"list[current_player;main;0,".. 5.5+inv_offset .. ";8,4;]" ..

		-- listring stuff
		"listring[context;main]" ..
		"listring[current_player;main]"

	if has_technic then
		formspec = formspec ..
			-- technic upgrades
			"label[1,5.2;Upgrades]" ..
			"list[context;upgrade;4,5;4,1;]"
	end

	meta:set_string("formspec", formspec)
end
