local searchBtn = gurt.select('#searchButton')
local luckyBtn = gurt.select('#luckyButton')
local searchQuery = gurt.select('#searchQuery')
local loading = gurt.select('#loading')
local results = gurt.select('#results')
local stats = gurt.select('#stats')
local hideUnreachableChk = gurt.select('#hideUnreachable')

local hideUnreachable = hideUnreachableChk.value

local function showLoading()
    loading.classList:remove('hidden')
    local children = results.children
    for i = #children, 1, -1 do
        children[i]:remove()
    end
    stats.text = ''
end

local function displayResults(data)
    loading.classList:add('hidden')
    local children = results.children
    for i = #children, 1, -1 do
        children[i]:remove()
    end

    if not data.results or #data.results == 0 then
        local noResultsItem = gurt.create('div', {
            text = 'No results found for your query.',
            style = 'result-item'
        })
        results:append(noResultsItem)
        stats.text = 'No results found'
        return
    end

    local filteredResults = {}
    local hiddenCount = 0

    if hideUnreachable then
        for i, result in ipairs(data.results) do
            if result.is_online == nil or result.is_online then
                filteredResults[#filteredResults + 1] = result
            else
                hiddenCount = hiddenCount + 1
            end
        end
    else
        filteredResults = data.results
    end

    if #filteredResults == 0 then
        local msg = 'No reachable results found. Uncheck "Hide unreachable pages" to see everything.'
        local noResultsItem = gurt.create('div', {
            text = msg,
            style = 'result-item'
        })
        results:append(noResultsItem)

        local totalResults = data.total_results or #data.results
        if hiddenCount > 0 then
            stats.text = 'Found ' .. totalResults .. ' result' .. (totalResults == 1 and '' or 's') .. ' (' .. hiddenCount .. ' hidden)'
        else
            stats.text = '0 reachable results'
        end
        return
    end

    for i, result in ipairs(filteredResults) do
        local resultItem = gurt.create('div', { style = 'result-item' })

        resultItem:on('click', function()
            gurt.location.goto(result.url)
        end)

        local headerDiv = gurt.create('div', { style = 'result-header' })

        if result.icon and result.icon ~= '' then
            local iconImg = gurt.create('img', {
                src = result.icon,
                style = 'result-icon',
                alt = 'Site icon'
            })
            headerDiv:append(iconImg)
        end

        local titleDiv = gurt.create('p', {
            text = result.title or result.url,
            style = 'result-title'
        })
        headerDiv:append(titleDiv)

        local urlDiv = gurt.create('p', {
            text = result.url,
            style = 'result-url'
        })

        local previewText = result.preview or result.description or ''
        if #previewText > 150 then
            previewText = previewText:sub(1, 147) .. '...'
        end

        local previewDiv = gurt.create('p', {
            text = previewText,
            style = 'result-preview'
        })

        resultItem:append(headerDiv)
        resultItem:append(urlDiv)
        resultItem:append(previewDiv)
        results:append(resultItem)
    end

    local totalResults = data.total_results or #data.results
    local shownCount = #filteredResults

    if hiddenCount > 0 then
        stats.text = 'Showing ' .. shownCount .. ' of ' .. totalResults .. ' result' .. (totalResults == 1 and '' or 's') .. ' (' .. hiddenCount .. ' unreachable hidden)'
    else
        stats.text = 'Found ' .. totalResults .. ' result' .. (totalResults == 1 and '' or 's')
    end
end

local lastData = nil
local function cachedDisplayResults(data)
    lastData = data
    displayResults(data)
end

hideUnreachableChk:on('change', function(e)
    hideUnreachable = hideUnreachableChk.value
    if lastData then
        displayResults(lastData)
    end
end)

local function performSearch(query)
    if not query or query == '' then
        return
    end

    showLoading()

    local url = 'gurt://135.125.163.131:4880/api/search?q=' .. urlEncode(query) .. '&per_page=20'
    local response = fetch(url, {
        method = 'GET'
    })

    if response:ok() then
        local data = response:json()
        cachedDisplayResults(data)
    else
        loading.classList:add('hidden')
        local children = results.children
        for i = #children, 1, -1 do
            children[i]:remove()
        end
        stats.text = 'Search failed: ' .. response.status .. ' ' .. response.statusText
    end
end

local function performLuckySearch()
    showLoading()
    local luckyTerms = {'test', 'demo', 'api', 'web', 'site', 'page', 'home', 'index'}
    local randomTerm = luckyTerms[math.random(#luckyTerms)]
    local url = 'gurt://135.125.163.131:4880/api/search?q=' .. urlEncode(randomTerm) .. '&per_page=50'
    local response = fetch(url, {
        method = 'GET'
    })

    if response:ok() then
        local data = response:json()
        if data.results and #data.results > 0 then
            local randomResult = data.results[math.random(#data.results)]
            gurt.location.goto(randomResult.url)
        else
            loading.classList:add('hidden')
            local children = results.children
            for i = #children, 1, -1 do
                children[i]:remove()
            end
            stats.text = 'No sites available for lucky search'
        end
    else
        loading.classList:add('hidden')
        local children = results.children
        for i = #children, 1, -1 do
            children[i]:remove()
        end
        stats.text = 'Lucky search failed'
    end
end

searchBtn:on('click', function()
    local query = searchQuery.value
    if query and query ~= '' then
        performSearch(query:trim())
    end
end)

luckyBtn:on('click', function()
    performLuckySearch()
end)

searchQuery:on('keydown', function(e)
    if e.key == 'Enter' then
        local query = searchQuery.value
        if query and query ~= '' then
            performSearch(query:trim())
        end
    elseif e.key == 'Escape' then
        searchQuery.value = ''
        local children = results.children
        for i = #children, 1, -1 do
            children[i]:remove()
        end
        stats.text = ''
        loading.classList:add('hidden')
        local baseUrl = gurt.location.pathname
        if gurt.location.href ~= baseUrl then
            gurt.location.goto(baseUrl)
        end
    end
end)

local function checkForQueryParam()
    local url = gurt.location.href
    local queryIndex = url:find('?')

    if queryIndex then
        local queryString = url:sub(queryIndex + 1)
        local params = {}
        for param in queryString:gmatch('([^&]+)') do
            local key, value = param:match('([^=]+)=(.+)')
            if key and value then
                params[key] = urlDecode(value)
            end
        end
        if params.q then
            searchQuery.value = params.q
            performSearch(params.q)
            return
        end
    end

    searchQuery:focus()
end

searchQuery:on('input', function()
    local query = searchQuery.value:trim()
    if query == '' then
        local children = results.children
        for i = #children, 1, -1 do
            children[i]:remove()
        end
        stats.text = ''
        loading.classList:add('hidden')
        local baseUrl = gurt.location.pathname
        if gurt.location.href ~= baseUrl then
            gurt.location.goto(baseUrl)
        end
    end
end)

checkForQueryParam()
