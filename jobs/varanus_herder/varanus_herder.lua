local VaranusHerderClass = class()
local ShepherdClass = require ('stonehearth.jobs.shepherd.shepherd')
radiant.mixin(VaranusHerderClass, ShepherdClass)
-- promote_to varanus_herder:jobs:varanus_herder
return VaranusHerderClass
