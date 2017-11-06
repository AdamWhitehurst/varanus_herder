local ShepherdClass = class()
local rng = _radiant.math.get_default_rng()
local BaseJob = require 'jobs.base_job'
radiant.mixin(ShepherdClass, BaseJob)

--- Public functions, required for all classes
function ShepherdClass:initialize()
   BaseJob.initialize(self)
   self._sv.last_found_critter_time = nil
   self._sv.trailed_animals = nil
   self._sv.num_trailed_animals = 0
end

function ShepherdClass:demote()
   BaseJob.demote(self)

   --Orphan all the animals
   self:_abandon_following_animals()

   self.__saved_variables:mark_changed()
end

-- Note we could get destroyed without being demoted, so we do need to clean up on destroy
function ShepherdClass:destroy()
   if self._sv.is_current_class then
      self:_abandon_following_animals()
   end

   BaseJob.destroy(self)
end

-- Shepherd related functionality

-- Add an animal to the list following the varanus_herder
function ShepherdClass:add_trailing_animal(animal, pasture)
   if not self._sv.trailed_animals then
      self._sv.trailed_animals = {}
      self._sv.num_trailed_animals = 0
   end
   self._sv.trailed_animals[animal:get_id()] = animal
   self._sv.num_trailed_animals = self._sv.num_trailed_animals + 1

   --If we have the varanus_herder_speed_buff, make sure the added critter gets the buff too
   if self:has_perk('varanus_herder_speed_up_1') then
      radiant.entities.add_buff(animal, 'stonehearth:buffs:varanus_herder:speed_1');
   end

   self:_on_interacted_with_animal(animal)

   if self._varanus_herdering_buff then
      self._varanus_herdering_buff:get_script_controller():on_trailing_animals_updated()
   end
   --Fire an event saying that we've collected an animal
   radiant.events.trigger(self._sv._entity, 'stonehearth:add_trailing_animal', {animal = animal, pasture = pasture})
end

function ShepherdClass:get_trailing_animals()
   return self._sv.trailed_animals, self._sv.num_trailed_animals
end

--Remove the animal from the varanus_herder's list. 
function ShepherdClass:remove_trailing_animal(animal_id)
   if not self._sv.trailed_animals then
      return
   end

   --If the animal had the speed buff, remove it
   if self._sv.trailed_animals[animal_id] and self:has_perk('varanus_herder_speed_up_1') then
      radiant.entities.remove_buff(self._sv.trailed_animals[animal_id], 'stonehearth:buffs:varanus_herder:speed_1')
   end

   self._sv.trailed_animals[animal_id] = nil
   self._sv.num_trailed_animals = self._sv.num_trailed_animals - 1

   assert(self._sv.num_trailed_animals >= 0, 'varanus_herder trying to remove animals he does not have')

   if self._varanus_herdering_buff then
      self._varanus_herdering_buff:get_script_controller():on_trailing_animals_updated()
   end
end

--Returns true if the varanus_herder was able to find an animal, false otherwise
--Depends on % bonus chance that increases as Shepherd levels, and time since last
--critter was found. 
--Starting varanus_herder: 100% chance if we've never found a critter before
--0% chance if we JUST found another critter
--100% chance if 24 in game hours have past since the last critter
--As varanus_herder levels up, bonus is added to % chance
function ShepherdClass:can_find_animal_in_world()
   if radiant.entities.has_buff(self._sv._entity, 'stonehearth:buffs:varanus_herder:stenched') then
      -- Stenched varanus_herders don't find animals for a while
      return false
   end
   
   local curr_elapsed_time = stonehearth.calendar:get_elapsed_time()
   local constants = stonehearth.calendar:get_constants()
   if not self._sv.last_found_critter_time then
      self._sv.last_found_critter_time = curr_elapsed_time
      return true
   else
      --Calc difference between curr time and last found critter time
      local elapsed_difference = curr_elapsed_time - self._sv.last_found_critter_time
      --convert ms to hours
      local elapsed_hours = elapsed_difference / (constants.seconds_per_minute*constants.minutes_per_hour)
      local percent_chance = (elapsed_hours / constants.hours_per_day) * 100
      if self:has_perk('varanus_herder_improved_find_rate') then
         percent_chance = percent_chance * 2
      end
      
      local attributes = self._sv._entity:get_component('stonehearth:attributes')
      if attributes then
         local compassion = attributes:get_attribute('compassion') or 0
         local bonus_chance = compassion * stonehearth.constants.attribute_effects.COMPASSION_SHEPHERD_SHEEP_MULTIPLIER
         percent_chance = percent_chance + bonus_chance
      end

      local roll = rng:get_int(1, 100)  
      if roll < percent_chance then
         self._sv.last_found_critter_time = curr_elapsed_time
         return true
      end
   end
   return false
end

-- Private Functions
function ShepherdClass:_create_listeners()
   self._xp_listeners = {}

   table.insert(self._xp_listeners, radiant.events.listen(self._sv._entity, 'stonehearth:tame_animal', self, self._on_animal_tamed))
   table.insert(self._xp_listeners, radiant.events.listen(self._sv._entity, 'stonehearth:gather_renewable_resource', self, self._on_renewable_resource_gathered))
   table.insert(self._xp_listeners, radiant.events.listen(self._sv._entity, 'stonehearth:gather_resource', self, self._on_resource_gathered))
   table.insert(self._xp_listeners, radiant.events.listen(self._sv._entity, 'stonehearth:feed_pasture', self, self._on_pasture_fed))
end

function ShepherdClass:_remove_listeners()
   if self._xp_listeners then
      for i, listener in ipairs(self._xp_listeners) do
         listener:destroy()
      end
      self._xp_listeners = nil
   end
end

-- When we tame an animal, grant some XP
-- TODO: maybe vary the XP based on the kind of animal?
function ShepherdClass:_on_animal_tamed(args)
   self._job_component:add_exp(self._xp_rewards['tame_animal'])
end

function ShepherdClass:_on_pasture_fed(args)
   self._job_component:add_exp(self._xp_rewards['feed_pasture'])
end

--Grant some XP if we harvest renwable resources off an animal
function ShepherdClass:_on_renewable_resource_gathered(args)
   if args.harvested_target then
      local equipment_component = args.harvested_target:get_component('stonehearth:equipment')
      if equipment_component and equipment_component:has_item_type('stonehearth:pasture_equipment:tag') then
         self._job_component:add_exp(self._xp_rewards['harvest_animal_resources'])
         self:_on_interacted_with_animal(args.harvested_target)
      end
   end
   if args.spawned_item and self:has_perk('varanus_herder_extra_bonuses') then
      local spawned_uri = args.spawned_item:get_uri()
      local source_location = radiant.entities.get_world_grid_location(self._sv._entity)
      local placement_point = radiant.terrain.find_placement_point(source_location, 1, 5)
      if not placement_point then
         placement_point = source_location
      end
      local extra_harvest = radiant.entities.create_entity(spawned_uri, { owner = self._sv._entity })
      radiant.terrain.place_entity(extra_harvest, placement_point)
      local player_id = radiant.entities.get_player_id(self._sv._entity)
      local inventory = stonehearth.inventory:get_inventory(player_id)
      if inventory then
         inventory:add_item_if_not_full(extra_harvest)
      end
   end
end

function ShepherdClass:_on_resource_gathered(args)
   if args.harvested_target then
      local equipment_component = args.harvested_target:get_component('stonehearth:equipment')
      if equipment_component and equipment_component:has_item_type('stonehearth:pasture_equipment:tag') then
         self._job_component:add_exp(self._xp_rewards['harvest_animal'])
         radiant.entities.add_buff(self._sv._entity, 'stonehearth:buffs:varanus_herder:stenched');
      end
   end
end

--Remove their tags and make sure they are free from their pasture
function ShepherdClass:_abandon_following_animals()
   if self._sv.trailed_animals then
      for id, animal in pairs(self._sv.trailed_animals) do
         --Free self from pasture and tag
         local equipment_component = animal:get_component('stonehearth:equipment')
         local pasture_tag = equipment_component:has_item_type('stonehearth:pasture_equipment:tag')
         local varanus_herdered_animal_component = pasture_tag:get_component('stonehearth:varanus_herdered_animal')
         varanus_herdered_animal_component:free_animal()
      end
      self._sv.trailed_animals = nil
   end
end

function ShepherdClass:set_varanus_herdering(is_varanus_herdering)
   if not self._is_varanus_herdering and is_varanus_herdering then
      self._varanus_herdering_buff = radiant.entities.add_buff(self._sv._entity, 'stonehearth:buffs:varanus_herdering');
   elseif self._is_varanus_herdering and not is_varanus_herdering then
      if self._varanus_herdering_buff then
         self._varanus_herdering_buff:destroy()
         self._varanus_herdering_buff = nil
      end
   end
   self._is_varanus_herdering = is_varanus_herdering
end

function ShepherdClass:_on_interacted_with_animal(animal)
   --Chance to add Cared For buff to animal
   local attributes = self._sv._entity:get_component('stonehearth:attributes')
   if attributes then
      local compassion = attributes:get_attribute('compassion') or 0
      local buff_chance = compassion * stonehearth.constants.attribute_effects.COMPASSION_SHEPHERD_BUFF_CHANCE_MULTIPLIER
      local roll = rng:get_int(1, 100)  
      if roll <= buff_chance then
         radiant.entities.add_buff(animal, 'stonehearth:buffs:varanus_herder:compassionate_varanus_herder');
      end
   end
end

return ShepherdClass
