local config = {
	crossbow_uses = 50,
	arrow_lifetime = 180,
}

-- Legacy Config Support

for name, _ in pairs(config) do
	local global = "SHOOTER_"..name:upper()
	if minetest.global_exists(global) then
		config[name] = _G[global]
	end
	local setting = minetest.settings:get("shooter_"..name)
	if type(setting) == "string" then
		config[name] = tonumber(setting)
	end
end

local arrow_tool_caps = {damage_groups={fleshy=2}}
if minetest.global_exists("SHOOTER_ARROW_TOOL_CAPS") then
	arrow_tool_caps = table.copy(SHOOTER_ARROW_TOOL_CAPS)
end

minetest.register_alias("shooter_crossbow:arrow", "shooter_crossbow:arrow_white")
minetest.register_alias("shooter:crossbow_loaded", "shooter:crossbow_loaded_white")

local dye_basecolors = (dye and dye.basecolors) or
	{"white", "grey", "black", "red", "yellow", "green", "cyan", "blue", "magenta"}

local function get_animation_frame(dir)
	local angle = math.atan(dir.y)
	local frame = 90 - math.floor(angle * 360 / math.pi)
	if frame < 1 then
		frame = 1
	elseif frame > 180 then
		frame = 180
	end
	return frame
end

local function get_target_pos(p1, p2, dir, offset)
	local d = vector.distance(p1, p2) - offset
	local td = vector.multiply(dir, {x=d, y=d, z=d})
	return vector.add(p1, td)
end

-- name is the overlay texture name, colour is used to select the wool texture
local function get_texture(name, colour)
	return "wool_"..colour..".png^shooter_"..name..".png^[makealpha:255,126,126"
end

minetest.register_entity("shooter_crossbow:arrow_entity", {
	physical = false,
	visual = "mesh",
	mesh = "shooter_arrow.b3d",
	visual_size = {x=1, y=1},
	textures = {
		get_texture("arrow_uv", "white"),
	},
	color = "white",
	timer = 0,
	lifetime = config.arrow_lifetime,
	player = nil,
	state = "init",
	node_pos = nil,
	collisionbox = {0,0,0, 0,0,0},
	stop = function(self, pos)
		local acceleration = {x=0, y=-10, z=0}
		if self.state == "stuck" then
			pos = pos or self.object:getpos()
			acceleration = {x=0, y=0, z=0}
		end
		if pos then
			self.object:moveto(pos)
		end
		self.object:set_properties({
			physical = true,
			collisionbox = {-1/8,-1/8,-1/8, 1/8,1/8,1/8},
		})
		self.object:setvelocity({x=0, y=0, z=0})
		self.object:setacceleration(acceleration)
	end,
	strike = function(self, object)
		local puncher = self.player
		if puncher and shooter:is_valid_object(object) then
			if puncher ~= object then
				local dir = puncher:get_look_dir()
				local p1 = puncher:getpos()
				local p2 = object:getpos()
				local tpos = get_target_pos(p1, p2, dir, 0)
				shooter:spawn_particles(tpos, shooter.config.explosion_texture)
				object:punch(puncher, nil, arrow_tool_caps, dir)
			end
		end
		self:stop(object:getpos())
	end,
	on_activate = function(self, staticdata)
		self.object:set_armor_groups({immortal=1})
		if staticdata == "expired" then
			self.object:remove()
		end
	end,
	on_punch = function(self, puncher)
		if puncher then
			if puncher:is_player() then
				local stack = "shooter_crossbow:arrow_"..self.color
				local inv = puncher:get_inventory()
				if inv:room_for_item("main", stack) then
					inv:add_item("main", stack)
					self.object:remove()
				end
			end
		end
	end,
	on_step = function(self, dtime)
		if self.state == "init" then
			return
		end
		self.timer = self.timer + dtime
		self.lifetime = self.lifetime - dtime
		if self.lifetime < 0 then
			self.object:remove()
			return
		elseif self.state == "dropped" then
			return
		elseif self.state == "stuck" then
			if self.timer > 1 then
				if self.node_pos then
					local node = minetest.get_node(self.node_pos)
					if node.name then
						local item = minetest.registered_items[node.name]
						if item then
							if not item.walkable then
								self.state = "dropped"
								self:stop()
								return
							end
						end
					end
				end
				self.timer = 0
			end
			return
		end
		if self.timer > 0.2 then
			local dir = vector.normalize(self.object:getvelocity())
			local frame = get_animation_frame(dir)
			local p1 = vector.add(self.object:getpos(), dir)
			local p2 = vector.add(p1, vector.multiply(dir, 4))
			local ray = minetest.raycast(p1, p2, true, true)
			local pointed_thing = ray:next() or {}
			if pointed_thing.type == "object" then
				local obj = pointed_thing.ref
				if shooter:is_valid_object(obj) then
					self:strike(obj)
				end
			elseif pointed_thing.type == "node" then
				local pos = minetest.get_pointed_thing_position(pointed_thing, false)
				local node = minetest.get_node(pos)
				local target_pos = get_target_pos(p1, pos, dir, 0.66)
				self.node_pos = pos
				self.state = "stuck"
				self:stop(target_pos)
				shooter:play_node_sound(node, pos)
			end
			self.object:set_animation({x=frame, y=frame}, 0)
			self.timer = 0
		end
	end,
	get_staticdata = function(self)
		return "expired"
	end,
})

for _, color in pairs(dye_basecolors) do
	minetest.register_craftitem("shooter_crossbow:arrow_"..color, {
		description = color:gsub("%a", string.upper, 1).." Arrow",
		inventory_image = get_texture("arrow_inv", color),
	})
	minetest.register_tool("shooter_crossbow:crossbow_loaded_"..color, {
		description = "Crossbow",
		inventory_image = get_texture("crossbow_loaded", color),
		groups = {not_in_creative_inventory=1},
		on_use = function(itemstack, user, pointed_thing)
			minetest.sound_play("shooter_click", {object=user})
			if not minetest.setting_getbool("creative_mode") then
				itemstack:add_wear(65535/config.crossbow_uses)
			end
			itemstack = "shooter_crossbow:crossbow 1 "..itemstack:get_wear()
			local pos = user:getpos()
			local dir = user:get_look_dir()
			local yaw = user:get_look_yaw()
			if pos and dir and yaw then
				pos.y = pos.y + shooter.config.camera_height
				pos = vector.add(pos, dir)
				local obj = minetest.add_entity(pos, "shooter_crossbow:arrow_entity")
				local ent = nil
				if obj then
					ent = obj:get_luaentity()
				end
				if ent then
					ent.player = ent.player or user
					ent.state = "flight"
					ent.color = color
					obj:set_properties({
						textures = {get_texture("arrow_uv", color)}
					})
					minetest.sound_play("shooter_throw", {object=obj}) 
					local frame = get_animation_frame(dir)
					obj:setyaw(yaw + math.pi)
					obj:set_animation({x=frame, y=frame}, 0)
					obj:setvelocity({x=dir.x * 14, y=dir.y * 14, z=dir.z * 14})
					if pointed_thing.type ~= "nothing" then
						local ppos = minetest.get_pointed_thing_position(pointed_thing, false)
						local _, npos = minetest.line_of_sight(pos, ppos, 1)
						if npos then
							ppos = npos
							pointed_thing.type = "node"
						end
						if pointed_thing.type == "object" then
							ent:strike(pointed_thing.ref)
							return itemstack
						elseif pointed_thing.type == "node" then
							local node = minetest.get_node(ppos)
							local tpos = get_target_pos(pos, ppos, dir, 0.66)
							minetest.after(0.2, function(object, pos, npos)
								ent.node_pos = npos
								ent.state = "stuck"
								ent:stop(pos)
								shooter:play_node_sound(node, npos)
							end, obj, tpos, ppos)
							return itemstack
						end
					end
					obj:setacceleration({x=dir.x * -3, y=-5, z=dir.z * -3})
				end
			end
			return itemstack
		end,
	})
end

minetest.register_tool("shooter_crossbow:crossbow", {
	description = "Crossbow",
	inventory_image = "shooter_crossbow.png",
	on_use = function(itemstack, user, pointed_thing)
		local inv = user:get_inventory()
		local stack = inv:get_stack("main", user:get_wield_index() + 1)
		local color = string.match(stack:get_name(), "shooter_crossbow:arrow_(%a+)")
		if color then
			minetest.sound_play("shooter_reload", {object=user})
			if not minetest.setting_getbool("creative_mode") then
				inv:remove_item("main", "shooter_crossbow:arrow_"..color.." 1")
			end
			return "shooter_crossbow:crossbow_loaded_"..color.." 1 "..itemstack:get_wear()
		end
		for _, color in pairs(dye_basecolors) do
			if inv:contains_item("main", "shooter_crossbow:arrow_"..color) then
				minetest.sound_play("shooter_reload", {object=user})
				if not minetest.setting_getbool("creative_mode") then
					inv:remove_item("main", "shooter_crossbow:arrow_"..color.." 1")
				end
				return "shooter_crossbow:crossbow_loaded_"..color.." 1 "..itemstack:get_wear()
			end
		end
		minetest.sound_play("shooter_click", {object=user})
	end,
})

if shooter.config.enable_crafting == true then
	minetest.register_craft({
		output = "shooter_crossbow:crossbow",
		recipe = {
			{"default:stick", "default:stick", "default:stick"},
			{"default:stick", "default:stick", ""},
			{"default:stick", "", "default:bronze_ingot"},
		},
	})
	minetest.register_craft({
		output = "shooter_crossbow:arrow_white",
		recipe = {
			{"default:steel_ingot", "", ""},
			{"", "default:stick", "default:paper"},
			{"", "default:paper", "default:stick"},
		},
	})
	for _, color in pairs(dye_basecolors) do
		if color ~= "white" then
			minetest.register_craft({
				output = "shooter_crossbow:arrow_"..color,
				recipe = {
					{"", "dye:"..color, "shooter_crossbow:arrow_white"},
				},
			})
		end
	end
end

--Backwards compatibility
minetest.register_alias("shooter:crossbow", "shooter_crossbow:crossbow")
for _, color in pairs(dye_basecolors) do
	minetest.register_alias("shooter:arrow_"..color, "shooter_crossbow:arrow_"..color)
	minetest.register_alias("shooter:crossbow_loaded_"..color, "shooter_crossbow:crossbow_loaded_"..color)
end
