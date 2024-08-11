tm.physics.AddTexture("1texture.png", "terrain_atlas")

-- Perlin noise implementation
local function fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(t, a, b)
    return a + t * (b - a)
end

local function grad(hash, x, y, z)
    local h = hash % 16
    local u = h < 8 and x or y
    local v = h < 4 and y or (h == 12 or h == 14) and x or z
    return ((h % 2) == 0 and u or -u) + ((h % 3) == 0 and v or -v)
end

local permutation = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
    8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
    35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
    134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
    55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
    18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
    250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
    189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
    228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
    107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
}

local function noise(x, y, z)
    local X = math.floor(x) % 256
    local Y = math.floor(y) % 256
    local Z = math.floor(z) % 256
    x = x - math.floor(x)
    y = y - math.floor(y)
    z = z - math.floor(z)
    local u = fade(x)
    local v = fade(y)
    local w = fade(z)
    local A  = permutation[X+1] + Y
    local AA = permutation[A % 256 + 1] + Z
    local AB = permutation[(A + 1) % 256 + 1] + Z
    local B  = permutation[(X + 1) % 256 + 1] + Y
    local BA = permutation[B % 256 + 1] + Z
    local BB = permutation[(B + 1) % 256 + 1] + Z

    return lerp(w, lerp(v, lerp(u, grad(permutation[AA % 256 + 1], x, y, z),
                                   grad(permutation[BA % 256 + 1], x-1, y, z)),
                           lerp(u, grad(permutation[AB % 256 + 1], x, y-1, z),
                                   grad(permutation[BB % 256 + 1], x-1, y-1, z))),
                   lerp(v, lerp(u, grad(permutation[(AA + 1) % 256 + 1], x, y, z-1),
                                   grad(permutation[(BA + 1) % 256 + 1], x-1, y, z-1)),
                           lerp(u, grad(permutation[(AB + 1) % 256 + 1], x, y-1, z-1),
                                   grad(permutation[(BB + 1) % 256 + 1], x-1, y-1, z-1))))
end

-- Generate base terrain heightmap
local function generate_base_heightmap(width, height, scale, octaves, persistence, lacunarity)
    local heightmap = {}
    for x = 1, width do
        heightmap[x] = {}
        for z = 1, height do
            local amplitude = 1
            local frequency = 1
            local noiseHeight = 0
            
            for i = 1, octaves do
                local sampleX = (x - 1) / width * scale * frequency
                local sampleZ = (z - 1) / height * scale * frequency
                
                local perlinValue = noise(sampleX, sampleZ, 0)
                noiseHeight = noiseHeight + perlinValue * amplitude
                
                amplitude = amplitude * persistence
                frequency = frequency * lacunarity
            end
            
            heightmap[x][z] = noiseHeight
        end
    end
    return heightmap
end

-- Smooth tile edges
local function smooth_tile_edges(heightmap, tile_width, tile_height)
    local blend_distance = 4  -- Adjust as needed
    for x = 1, #heightmap do
        for z = 1, #heightmap[1] do
            local tile_x = (x - 1) % tile_width
            local tile_z = (z - 1) % tile_height
            local blend_factor_x = math.min(tile_x, tile_width - tile_x) / blend_distance
            local blend_factor_z = math.min(tile_z, tile_height - tile_z) / blend_distance
            local edge_factor = math.min(blend_factor_x, blend_factor_z, 1)
            if edge_factor < 1 then
                local neighbors = {}
                for dx = -1, 1 do
                    for dz = -1, 1 do
                        local nx, nz = x + dx * tile_width, z + dz * tile_height
                        if heightmap[nx] and heightmap[nx][nz] then
                            table.insert(neighbors, heightmap[nx][nz])
                        end
                    end
                end
                local avg_height = 0
                for _, h in ipairs(neighbors) do
                    avg_height = avg_height + h
                end
                avg_height = avg_height / #neighbors
                heightmap[x][z] = heightmap[x][z] * edge_factor + avg_height * (1 - edge_factor)
            end
        end
    end
    return heightmap
end

-- Apply terrain features
local function apply_terrain_features(heightmap, width, height)
    local feature_noise = generate_base_heightmap(width, height, 3, 4, 0.5, 2.0)
    local mountain_noise = generate_base_heightmap(width, height, 2, 3, 0.6, 2.2)
    local detail_noise = generate_base_heightmap(width, height, 10, 3, 0.4, 2.5)
    
    for x = 1, width do
        for z = 1, height do
            local feature = feature_noise[x][z]
            local mountain = mountain_noise[x][z]
            local detail = detail_noise[x][z]
            
            if feature < -0.7 then
                -- Deep canyons
                heightmap[x][z] = heightmap[x][z] * 0.05 - 0.5
            elseif feature < -0.5 then
                -- Riverbeds
                heightmap[x][z] = heightmap[x][z] * 0.2 + detail * 0.05
            elseif feature < -0.3 then
                -- Valleys
                heightmap[x][z] = heightmap[x][z] * 0.4 + detail * 0.1
            elseif feature < -0.1 then
                -- Plains
                heightmap[x][z] = heightmap[x][z] * 0.6 + detail * 0.05
            elseif feature < 0.1 then
                -- Rolling hills
                heightmap[x][z] = heightmap[x][z] * 0.8 + detail * 0.2
            elseif feature < 0.3 then
                -- Hills
                heightmap[x][z] = heightmap[x][z] * 1.2 + detail * 0.3
            elseif feature < 0.5 then
                -- Ridges
                heightmap[x][z] = heightmap[x][z] * 1.5 + detail * 0.4
            elseif feature < 0.7 then
                -- Plateaus
                heightmap[x][z] = math.max(heightmap[x][z], 0.6) * 1.3 + detail * 0.2
            else
                -- Mountains
                if mountain > 0.8 then
                    -- Tall peaks
                    heightmap[x][z] = heightmap[x][z] * 7.0 + 2.0 + detail * 0.5
                elseif mountain > 0.6 then
                    -- Medium mountains
                    heightmap[x][z] = heightmap[x][z] * 5.0 + 1.5 + detail * 0.4
                else
                    -- Small mountains
                    heightmap[x][z] = heightmap[x][z] * 3.0 + 1.0 + detail * 0.3
                end
            end
            
            -- Normalize height, but allow for taller peaks and deeper canyons
            heightmap[x][z] = math.max(-1, math.min(4, heightmap[x][z]))
        end
    end
    
    return heightmap
end

-- Smooth the heightmap
local function smooth_heightmap(heightmap, width, height, smoothing_passes)
    for _ = 1, smoothing_passes do
        local smoothed = {}
        for x = 1, width do
            smoothed[x] = {}
            for z = 1, height do
                local sum = 0
                local count = 0
                for dx = -1, 1 do
                    for dz = -1, 1 do
                        local nx, nz = x + dx, z + dz
                        if nx >= 1 and nx <= width and nz >= 1 and nz <= height then
                            sum = sum + heightmap[nx][nz]
                            count = count + 1
                        end
                    end
                end
                smoothed[x][z] = sum / count
            end
        end
        heightmap = smoothed
    end
    return heightmap
end

-- Generate OBJ file content for a single tile
local function generate_obj_tile(start_x, start_z, end_x, end_z, heightmap, amplitude, total_width, total_height, tile_scale, uv_scale_mountain, uv_scale_plains, uv_scale_other, small_polygon_height)
    local vertices = {}
    local normals = {}
    local uvs = {}
    local obj = ""

    local heightmap_width = #heightmap
    local heightmap_height = #heightmap[1]

    -- Pre-calculate normals
    local normal_map = {}
    for x = 1, heightmap_width do
        normal_map[x] = {}
        for z = 1, heightmap_height do
            local left = heightmap[math.max(1, x-1)][z]
            local right = heightmap[math.min(heightmap_width, x+1)][z]
            local up = heightmap[x][math.max(1, z-1)]
            local down = heightmap[x][math.min(heightmap_height, z+1)]
            
            local nx = left - right
            local nz = up - down
            local ny = 2.0
            local length = math.sqrt(nx*nx + ny*ny + nz*nz)
            normal_map[x][z] = {nx/length, ny/length, nz/length}
        end
    end

    -- Generate vertices, normals, and UVs
    local mountain_threshold = 0.01
    local plains_threshold = 0.001

    local tile_width = end_x - start_x + 1
    local tile_height = end_z - start_z + 1

    for x = start_x, end_x do
        for z = start_z, end_z do
            local real_x = x
            local real_z = z
            local height = heightmap[real_x][real_z]
            local y = height * amplitude
            table.insert(vertices, string.format("v %f %f %f\n", -real_x * 41.66667 * tile_scale, y * tile_scale, -real_z * 41.66667 * tile_scale))
            
            local normal = normal_map[real_x][real_z]
            table.insert(normals, string.format("vn %f %f %f\n", normal[1], normal[2], normal[3]))
            
            -- Calculate base UV coordinates
            local u = (x - start_x) / (tile_width - 1)
            local v = (z - start_z) / (tile_height - 1)

            -- Determine terrain type and apply UV scaling with blending
            local mountain_factor = math.min(math.max((height - plains_threshold) / (mountain_threshold - plains_threshold), 0), 1)
            local plains_factor = 1 - mountain_factor
            local other_factor = math.max(1 - mountain_factor - plains_factor, 0)

            -- Apply UV scaling for each terrain type
            local u_mountain = u * uv_scale_mountain
            local v_mountain = v * uv_scale_mountain
            local u_plains = u * uv_scale_plains
            local v_plains = v * uv_scale_plains
            local u_other = u * uv_scale_other
            local v_other = v * uv_scale_other

            -- Blend UV coordinates
            local final_u = (u_mountain * mountain_factor + u_plains * plains_factor + u_other * other_factor) % 0.5
            local final_v = (v_mountain * mountain_factor + v_plains * plains_factor + v_other * other_factor) % 0.5

            -- Adjust UV coordinates to the correct quadrant
            if mountain_factor > 0.5 then
                final_u = final_u
                final_v = final_v
            elseif plains_factor > 0.5 then
                final_u = final_u
                final_v = final_v + 0.5
            else
                final_u = final_u + 0.5
                final_v = final_v
            end

            -- Apply a small offset to avoid precision issues
            final_u = math.min(math.max(final_u, 0.001), 0.999)
            final_v = math.min(math.max(final_v, 0.001), 0.999)
            
            table.insert(uvs, string.format("vt %f %f\n", final_u, final_v))
        end
    end

    -- Add small polygon vertices
    local small_poly_size = 10
    table.insert(vertices, string.format("v %f %f %f\n", -start_x * 41.66667 * tile_scale, small_polygon_height, -start_z * 41.66667 * tile_scale))
    table.insert(vertices, string.format("v %f %f %f\n", (-start_x + small_poly_size) * 41.66667 * tile_scale, small_polygon_height, -start_z * 41.66667 * tile_scale))
    table.insert(vertices, string.format("v %f %f %f\n", -start_x * 41.66667 * tile_scale, small_polygon_height, (-start_z + small_poly_size) * 41.66667 * tile_scale))

    table.insert(normals, "vn 0 1 0\n")
    table.insert(normals, "vn 0 1 0\n")
    table.insert(normals, "vn 0 1 0\n")
    table.insert(uvs, "vt 0 0.5\n")
    table.insert(uvs, "vt 0.25 0.5\n")
    table.insert(uvs, "vt 0 0.75\n")

    obj = obj .. table.concat(vertices)
    obj = obj .. table.concat(uvs)
    obj = obj .. table.concat(normals)

    -- Generate faces
    local vertex_index = 1
    for x = 1, tile_width - 1 do
        for z = 1, tile_height - 1 do
            local i1 = vertex_index
            local i2 = vertex_index + 1
            local i3 = vertex_index + tile_height
            local i4 = i3 + 1
            obj = obj .. string.format("f %d/%d/%d %d/%d/%d %d/%d/%d\n", i1, i1, i1, i2, i2, i2, i3, i3, i3)
            obj = obj .. string.format("f %d/%d/%d %d/%d/%d %d/%d/%d\n", i2, i2, i2, i4, i4, i4, i3, i3, i3)
            vertex_index = vertex_index + 1
        end
        vertex_index = vertex_index + 1
    end

    -- Add small polygon face (to prevent meshes from not rendering at distance in-game)
    local small_poly_start = #vertices - 2
    obj = obj .. string.format("f %d/%d/%d %d/%d/%d %d/%d/%d\n", small_poly_start, small_poly_start, small_poly_start, 
                               small_poly_start + 1, small_poly_start + 1, small_poly_start + 1, 
                               small_poly_start + 2, small_poly_start + 2, small_poly_start + 2)

    return obj
end

-- Function to estimate terrain complexity
local function estimate_complexity(heightmap, width, height)
    local complexity = 0
    for x = 2, width do
        for z = 2, height do
            local height_diff = math.abs(heightmap[x][z] - heightmap[x-1][z]) +
            math.abs(heightmap[x][z] - heightmap[x][z-1])
            complexity = complexity + height_diff
        end
    end
    return complexity / (width * height)
end

-- Generate and save OBJ files for multiple tiles
local function generate_terrain(width, height, base_tile_count, tile_width, scale, octaves, persistence, lacunarity, amplitude, smoothing_passes, tile_scale, uv_scale_mountain, uv_scale_plains, uv_scale_other, small_polygon_height)
    -- Ensure the heightmap is large enough for all potential tiles
    local max_tile_count = 8 
    local required_width = max_tile_count * tile_width + 1
    local required_height = required_width

    width = math.max(width, required_width)
    height = math.max(height, required_height)

    local heightmap = generate_base_heightmap(width, height, scale, octaves, persistence, lacunarity)
    heightmap = smooth_tile_edges(heightmap, tile_width, tile_width)
    heightmap = apply_terrain_features(heightmap, width, height)
    heightmap = smooth_heightmap(heightmap, width, height, smoothing_passes)

    -- Estimate terrain complexity
    local complexity = estimate_complexity(heightmap, width, height)
    
    -- Determine the number of tiles based on complexity
    local complexity_factor = math.ceil(complexity * 50)
    local tile_count = math.min(math.max(base_tile_count * complexity_factor, base_tile_count), max_tile_count)
    
    -- Ensure the total width is divisible by tile_width
    local total_width = (tile_count * tile_width) + tile_width / 2
    local total_height = (tile_count * tile_width) + tile_width / 2 
    
    tm.os.Log(string.format("Estimated complexity: %f, Using %dx%d tiles", complexity, tile_count, tile_count))

    local generated_files = {}  -- To keep track of generated files
    local overlap = 2

    for tx = 0, tile_count - 1 do
        for tz = 0, tile_count - 1 do
            local start_x = tx * (tile_width - overlap) + 1
            local start_z = tz * (tile_width - overlap) + 1
            local end_x = start_x + tile_width - 1
            local end_z = start_z + tile_width - 1
            local obj_content = generate_obj_tile(start_x, start_z, end_x, end_z, heightmap, amplitude, total_width, total_height, tile_scale, uv_scale_mountain, uv_scale_plains, uv_scale_other, small_polygon_height)
            local file_name = string.format("terrain_tile_%d_%d.obj", tx, tz)
            tm.os.WriteAllText_Dynamic(file_name, obj_content)
            tm.os.Log(string.format("Generated tile %s", file_name))
            table.insert(generated_files, file_name)
        end
    end

    return generated_files
end

-- Function to add and spawn meshes
local function add_and_spawn_meshes(generated_files, texture_name, spawn_height)
    local spawned_objects = {}
    for _, file_name in ipairs(generated_files) do
        -- Construct the full path to the mesh file
        local full_path = "data_dynamic_willNotBeUploadedToWorkshop/" .. file_name
        
        local resource_name = "terrain_" .. file_name:match("terrain_tile_(%d+_%d+)")
        tm.physics.AddMesh(full_path, resource_name)
        
        -- Spawn the mesh at the specified height
        local position = tm.vector3.Create(0, spawn_height, 0)
        local spawned_object = tm.physics.SpawnCustomObjectConcave(position, resource_name, texture_name)
        table.insert(spawned_objects, spawned_object)
        
        tm.os.Log(string.format("Spawned mesh: %s", resource_name))
    end
    return spawned_objects
end

-- Function to save generation state
local function save_generation_state(generated_files)
    local state = {
        generated = true,
        files = generated_files
    }
    local success, err = pcall(function()
        local json_string = json.serialize(state)
        tm.os.WriteAllText_Dynamic("terrain_generation_state.json", json_string)
    end)
    if not success then
        tm.os.Log("Failed to save terrain generation state: " .. tostring(err))
    end
end

-- Function to load generation state
local function load_generation_state()
    local success, state_json = pcall(tm.os.ReadAllText_Dynamic, "terrain_generation_state.json")
    if success and state_json and state_json ~= "" then
        local parse_success, state = pcall(json.parse, state_json)
        if parse_success then
            return state
        else
            tm.os.Log("Failed to parse terrain generation state JSON")
        end
    end
    return nil
end

-- Main terrain generation and spawning function
local function generate_and_spawn_terrain()
    -- Parameters
    local base_tile_count = 2
    local tile_width = 8
    local width = base_tile_count * tile_width + 1
    local height = width
    local scale = 5
    local octaves = 8
    local persistence = 0.55
    local lacunarity = 2.2
    local amplitude = 300
    local smoothing_passes = 2
    local tile_scale = 0.2
    local uv_scale_mountain = 30
    local uv_scale_plains = 30
    local uv_scale_other = 30
    local texture_name = "terrain_atlas"
    local spawn_height = 500
    local small_polygon_height = -15000

    -- Check if terrain has already been generated
    local state = load_generation_state()
    local generated_files

    if state and state.generated and state.files then
        tm.os.Log("Terrain already generated. Loading existing meshes.")
        generated_files = state.files
    else
        tm.os.Log("Generating new terrain...")
        generated_files = generate_terrain(width, height, base_tile_count, tile_width, scale, octaves, persistence, lacunarity, amplitude, smoothing_passes, tile_scale, uv_scale_mountain, uv_scale_plains, uv_scale_other, small_polygon_height)
        save_generation_state(generated_files)
    end

    -- Add and spawn meshes
    local spawned_objects = add_and_spawn_meshes(generated_files, texture_name, spawn_height)

    tm.os.Log("All terrain meshes have been added and spawned.")
end

-- Call the main function
generate_and_spawn_terrain()