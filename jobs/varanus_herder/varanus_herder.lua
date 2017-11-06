local rng = _radiant.math.get_default_rng()
local BaseJob = require 'stonehearth.jobs.base_job'
local ShepherdClass = require 'stonehearth.jobs.shepherd.shepherd'
radiant.mixin(ShepherdClass, BaseJob)
local VaranusHerderClass = class()
radiant.mixin(VaranusHerderClass, ShepherdClass)

--- Public functions, required for all classes
function VaranusHerderClass:initialize()
   BaseJob.initialize(self)
   ShepherdClass.initialize(self)
   self._sv.last_found_critter_time = nil
   self._sv.trailed_animals = nil
   self._sv.num_trailed_animals = 0
end

function VaranusHerderClass:demote()
   ShepherdClass.demote(self)

   --Orphan all the animals
   self:_abandon_following_animals()

   self.__saved_variables:mark_changed()
end

-- Note we could get destroyed without being demoted, so we do need to clean up on destroy
function VaranusHerderClass:destroy()
   if self._sv.is_current_class then
      self:_abandon_following_animals()
   end

   ShepherdClass.destroy(self)
end

return VaranusHerderClass
