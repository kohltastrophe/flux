local results = require("./Sert").run({
	-- async = require "./async.test",
})

if results.FAILED > 0 then
	error("Tests failed", 0)
end

return results
