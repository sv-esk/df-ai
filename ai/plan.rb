class DwarfAI
    class Plan
        attr_accessor :ai
        attr_accessor :tasks
        def initialize(ai)
            @ai = ai
            @tasks = []

            if w = df.world.buildings.all.grep(DFHack::BuildingWagonst).first
                df.building_deconstruct(w)
            end
        end

        def update
            nrdig = @tasks.count { |t| t[0] == :digroom }

            @tasks.delete_if { |t|
                case t[0]
                when :wantdig
                    # use precomputed nrdig to account for delete_if and
                    # ensure first :wantdig is dug first
                    if nrdig < 2
                        t[1][:queue] = false
                        t[1].dig
                        @tasks << [:digroom, t[1]]
                        nrdig += 1
                        true
                    end
                when :digroom
                    if t[1].dug?
                        construct_room(t[1])
                        true
                    end
                when :furnish
                    case t[1]
                    when :bed;    furnish_bed(t[2])
                    when :cab;    furnish_cabinet(t[2])
                    when :throne; furnish_throne(t[2])
                    when :door;   furnish_door(t[2])
                    when :workshop; construct_workshop(t[2])
                    end
                when :makeroom
                    makeroom(t[1])
                when :checkconstruct
                    checkconstruct(t[1])
                end
            }
        end

        def new_citizen(c)
            getbedroom(c.id)
        end

        def del_citizen(c)
            freebedroom(c.id)
            # TODO coffin/memorialslab for dead citizen
        end

        def getbedroom(id)
            if r = @rooms.find { |_r| _r.type == :bedroom and (not _r[:owner] or _r[:owner] == id) } || @rooms.find { |_r| _r.type == :bedroom and _r.status == :plan and not _r[:queue] }
                if r.status == :plan
                    r[:queue] = true
                    @tasks << [:wantdig, r]
                end
                set_owner(r, id)
                df.add_announcement("AI: assigned a bedroom to #{df.unit_find(id).name.to_s(false)}") { |ann| ann.pos = [r.x+1, r.y+1, r.z] }
            else
                puts "AI cant getbedroom(#{id})"
            end
        end

        def freebedroom(id)
            if r = @rooms.find { |_r| _r.type == :bedroom and _r[:owner] == id }
                set_owner(r, nil)
            end
        end

        def set_owner(r, id)
            r[:owner] = id
            u = df.unit_find(id) if id
            r[:furniture].to_a.each { |bld_id| df.building_setowner(df.building_find(bld_id), u) }
        end

        def construct_room(r)
            r.doors.length.times { furnish_door(r, true) }
            case r.type
            when :bedroom
                furnish_bed(r, true)
            when :workshop
                case r[:workshop]
                when :ManagersOffice
                    furnish_throne(r, true)
                else
                    @tasks << [:furnish, :workshop, r] if not construct_workshop(r)
                end
            when :stockpile
                construct_stockpile(r)
            end
        end

        def furnish_bed(r, queuenew=false)
            if bed = df.world.items.other[:BED].find { |i| i.kind_of?(DFHack::ItemBedst) and df.building_isitemfree(i) }
                bld = df.building_alloc(:Bed)
                if r.type == :bedroom
                    df.building_position(bld, [r.x+1, r.y+1, r.z])
                    df.building_construct(bld, [bed])
                    r[:bld_id] = bld.id
                    @tasks << [:makeroom, r]
                end
                (r[:furniture] ||= []) << bld.id
                true
            elsif queuenew
                check_workshop(:Carpenters)
                df.cuttrees(:any, 1, true) # need logs
                add_manager_order(:ConstructBed)
                @tasks << [:furnish, :bed, r]
            end
        end

        def furnish_cabinet(r, queuenew=false)
            if cab = df.world.items.other[:CABINET].find { |i| i.kind_of?(DFHack::ItemCabinetst) and df.building_isitemfree(i) }
                bld = df.building_alloc(:Cabinet)
                if r.type == :bedroom
                    nx = r.x+1
                    nx += (r.doors[0][0] > nx ? -1 : 1)
                    df.building_position(bld, [nx, r.y, r.z])
                    df.building_construct(bld, [cab])
                end
                (r[:furniture] ||= []) << bld.id
                true
            elsif queuenew
                check_workshop(:Masons)
                add_manager_order(:ConstructCabinet)
                @tasks << [:furnish, :cab, r]
            end
        end

        def furnish_throne(r, queuenew=false)
            if thr = df.world.items.other[:CHAIR].find { |i| i.kind_of?(DFHack::ItemChairst) and df.building_isitemfree(i) }
                bld = df.building_alloc(:Chair)
                if r.type == :workshop
                    df.building_position(bld, [r.x+1, r.y+1, r.z])
                    df.building_construct(bld, [thr])
                    r[:bld_id] = bld.id
                    @tasks << [:makeroom, r]
                end
                (r[:furniture] ||= []) << bld.id
                true
            elsif queuenew
                check_workshop(:Masons)
                add_manager_order(:ConstructThrone)
                @tasks << [:furnish, :throne, r]
            end
        end

        def furnish_door(r, queuenew=false)
            if dr = df.world.items.other[:DOOR].find { |i| i.kind_of?(DFHack::ItemDoorst) and df.building_isitemfree(i) }
                if p = r.doors.find { |x, y, z| !df.building_find(x, y, z) }
                    bld = df.building_alloc(:Door)
                    df.building_position(bld, p)
                    df.building_construct(bld, [dr])
                    (r[:furniture] ||= []) << bld.id
                end
                true
            elsif queuenew
                check_workshop(:Masons)
                add_manager_order(:ConstructDoor)
                @tasks << [:furnish, :door, r]
            end
        end

        def check_workshop(subtype)
            if not ws = @rooms.find { |r| r.type == :workshop and r[:workshop] == subtype } or ws.status == :plan
                ws ||= @rooms.find { |r| r.type == :workshop and not r[:workshop] and r.status == :plan }
                ws[:workshop] = subtype
                @tasks << [:digroom, ws]
                ws.dig
                df.add_announcement("AI: new workshop #{subtype}") { |ann| ann.pos = [ws.x+1, ws.y+1, ws.z] }

                case subtype
                when :Masons, :Carpenters
                    # add minimal stockpile in front of workshop
                    sptype = {:Masons => :stone, :Carpenters => :wood}[subtype]
                    # XXX hardcoded fort layout
                    y = (ws.doors[0][1] > ws.y1 ? ws.y2+2 : ws.y1-2)
                    sp = Room.new(:stockpile, ws.x1, ws.x2, y, y, ws.z1)
                    sp[:workshop] = ws
                    sp[:type] = sptype
                    @rooms << sp
                    @tasks << [:digroom, sp]
                    sp.dig

                    check_stockpile(sptype)
                end
            end
            ws
        end

        def check_stockpile(sptype)
            if sp = @rooms.find { |r| r.type == :stockpile and r[:type] == sptype and r.status == :plan and not r[:queue] }
                sp[:queue] = true
                @tasks << [:wantdig, sp]
            end
        end

        def construct_workshop(r)
            case r[:workshop]
            when :Well
                # need special items
            else
                # need only one boulder (TODO check economic stone)
                if bould = df.map_tile_at(r).mapblock.items.map { |idx| df.item_find(idx) }.find { |i|
                        i.kind_of?(DFHack::ItemBoulderst) and df.building_isitemfree(i) and i.pos.x >= r.x1 and i.pos.x <= r.x2 and i.pos.y >= r.y1 and i.pos.y <= r.y2
                } || df.world.items.other[:BOULDER].find { |i| i.kind_of?(DFHack::ItemBoulderst) and df.building_isitemfree(i) }
                    bld = df.building_alloc(:Workshop, r[:workshop])
                    df.building_position(bld, r)
                    df.building_construct(bld, [bould])
                    r[:bld_id] = bld.id
                    @tasks << [:checkconstruct, r]
                    true
                # XXX else quarry?
                end
            end
        end

        def construct_stockpile(r)
            bld = df.building_alloc(:Stockpile)
            df.building_position(bld, [r.x1, r.y1, r.z], r.w, r.h)
            bld.room.extents = df.malloc(r.w*r.h)
            bld.room.x = r.x1
            bld.room.y = r.y1
            bld.room.width = r.w
            bld.room.height = r.h
            r.w.times { |x| r.h.times { |y| bld.room.extents[x+r.w*y] = 1 } }
            df.building_construct_abstract(bld)
            r[:bld_id] = bld.id
            r.status = :finished

            case r[:type]
            when :stone
                bld.settings.flags.stone = true
                df.world.raws.inorganics.length.times { |i| bld.settings.stone[i] = 1 }
                bld.max_wheelbarrows = 1 if r.w > 1 and r.h > 1
            when :wood
                bld.settings.flags.wood = true
                df.world.raws.plants.all.length.times { |i| bld.settings.wood[i] = 1 }
            end

            if r[:workshop]
                if main = @rooms.find { |o| o.type == :stockpile and o[:type] == r[:type] and not o[:workshop] } and mb = main.dfbuilding
                    mb.give_to << bld
                    bld.take_from << mb
                end
            else
                @rooms.each { |o|
                    if o.type == :stockpile and o[:type] == r[:type] and o[:workshop] and sub = o.dfbuilding
                        bld.give_to << sub
                        sub.take_from << bld
                    end
                }
            end
        end

        def makeroom(r)
            bld = r.dfbuilding
            # TODO if not bld
            return if bld.getBuildStage < bld.getMaxBuildStage

            bld.room.extents = df.malloc((r.w+2)*(r.h+2))
            bld.room.x = r.x1-1
            bld.room.y = r.y1-1
            bld.room.width = r.w+2
            bld.room.height = r.h+2
            set_ext = lambda { |x, y, v| bld.room.extents[bld.room.width*(y-bld.room.y)+(x-bld.room.x)] = v }
            (r.x1-1 .. r.x2+1).each { |rx| (r.y1-1 .. r.y2+1).each { |ry|
                if df.map_tile_at(rx, ry, r.z).shape == :WALL
                    set_ext[rx, ry, 2]
                else
                    set_ext[rx, ry, 3]
                end
            } }
            r.doors.each { |x, y, z|
                set_ext[x, y, 0]
                # tile in front of the door tile is 4   (TODO door in corner...)
                set_ext[x+1, y, 4] if x < r.x1
                set_ext[x-1, y, 4] if x > r.x2
                set_ext[x, y+1, 4] if y < r.y1
                set_ext[x, y-1, 4] if y > r.y2
            }
            bld.is_room = 1

            r[:furniture].each { |f_id| df.building_linkrooms(df.building_find(f_id)) if f_id != bld.id }
            set_owner(r, r[:owner])

            if r.type == :bedroom
                furnish_cabinet(r, true)
            end

            r.status = :finished
            true
        end

        def checkconstruct(r)
            bld = r.dfbuilding
            return if bld and bld.getBuildStage < bld.getMaxBuildStage
            r.status = :finished
            true
        end

        def add_manager_order(order, amount=1)
            if not o = df.world.manager_orders.find { |_o| _o.job_type == order and _o.amount_total < 4 }
                o = DFHack::ManagerOrder.cpp_new(:job_type => order, :unk_2 => -1, :item_subtype => -1,
                        :mat_type => -1, :mat_index => -1, :hist_figure_id => -1, :amount_left => amount, :amount_total => amount)
                case order
                when :ConstructBed  # wood
                    o.material_category.wood = true
                when :ConstructTable, :ConstructThrone, :ConstructCabinet, :ConstructDoor  # rock
                    o.mat_type = 0
                else
                    p [:unknown_manager_material, order]
                end
                df.world.manager_orders << o
            else
                o.amount_total += amount
                o.amount_left += amount
            end
        end

        attr_accessor :fort_entrance, :rooms, :corridors
        def setup_blueprint
            # TODO use existing fort facilities (so we can relay the user or continue from a save)
            puts 'AI: setting up fort blueprint'
            scan_fort_entrance
            puts 'AI: blueprint found entrance'
            scan_fort_body
            puts 'AI: blueprint found body'
            setup_blueprint_rooms
            puts 'AI: blueprint found rooms'
        end

        # search a valid tile for fortress entrance
        def scan_fort_entrance
            # map center
            cx = df.world.map.x_count / 2
            cy = df.world.map.y_count / 2
            rangex = (-cx..cx).sort_by { |_x| _x.abs }
            rangey = (-cy..cy).sort_by { |_y| _y.abs }
            rangez = (0...df.world.map.z_count).to_a.reverse

            bestdist = 100000
            off = rangex.map { |_x|
                # test the whole map for 4x3 clean spots
                dy = rangey.find { |_y|
                    # can break because rangey is sorted by dist
                    break if _x.abs + _y.abs > bestdist
                    cz = rangez.find { |z|
                        t = df.map_tile_at(cx+_x, cy+_y, z) and t.shape == :FLOOR
                    }
                    next if not cz
                    (-1..2).all? { |__x|
                        (-1..1).all? { |__y|
                            t = df.map_tile_at(cx+_x+__x, cy+_y+__y, cz-1) and t.shape == :WALL and
                            tt = df.map_tile_at(cx+_x+__x, cy+_y+__y, cz) and tt.shape == :FLOOR and tt.designation.flow_size == 0 and not tt.designation.hidden and not df.building_find(tt)
                        }
                    }
                }
                bestdist = [_x.abs + dy.abs, bestdist].min if dy
                [_x, dy] if dy
                # find the closest to the center of the map
            }.compact.sort_by { |dx, dy| dx.abs + dy.abs }.first

            if off
                cx += off[0]
                cy += off[1]
            else
                puts 'AI: cant find fortress entrance spot'
            end
            cz = rangez.find { |z| t = df.map_tile_at(cx, cy, z) and t.shape == :FLOOR }

            @fort_entrance = Corridor.new(cx, cx+1, cy, cy, cz, cz)
        end

        # search how much we need to dig to find a spot for the full fortress body
        # here we cheat and work as if the map was fully reveal()ed
        def scan_fort_body
            # use a hardcoded fort layout
            cx, cy, cz = @fort_entrance.x, @fort_entrance.y, @fort_entrance.z
            @fort_entrance.z1 = (0..cz).to_a.reverse.find { |cz1|
                (-35..35).all? { |dx|
                    (-22..22).all? { |dy|
                        (-5..1).all? { |dz|
                            t = df.map_tile_at(cx+dx, cy+dy, cz1+dz) and t.shape == :WALL and
                            not t.designation.water_table and (t.tilemat == :STONE or t.tilemat == :MINERAL or (dz > -2 and t.tilemat == :SOIL))
                        }
                    }
                }
            }

            raise 'we need more minerals' if not @fort_entrance.z1
        end

        # assign rooms in the space found by scan_fort_*
        def setup_blueprint_rooms
            @rooms = []
            @corridors = []

            # hardcoded layout
            @corridors << @fort_entrance

            fx = @fort_entrance.x1
            fy = @fort_entrance.y1

            fz = @fort_entrance.z1
            setup_blueprint_workshops(fx, fy, fz, [@fort_entrance])
            
            fz = @fort_entrance.z1 -= 1
            setup_blueprint_stockpiles(fx, fy, fz, [@fort_entrance])
            
            fz = @fort_entrance.z1 -= 1
            setup_blueprint_utilities(fx, fy, fz, [@fort_entrance])
            
            2.times {
                fz = @fort_entrance.z1 -= 1
                setup_blueprint_bedrooms(fx, fy, fz, [@fort_entrance])
            }
        end

        def setup_blueprint_workshops(fx, fy, fz, entr)
            corridor_center = Corridor.new(fx-2, fx+2, fy-1, fy+1, fz, fz) 
            corridor_center.accesspath = entr
            @corridors << corridor_center

            # Quern, Millstone, Siege, Custom/soapmaker, Custom/screwpress
            # GlassFurnace, Kiln, magma workshops/furnaces, other nobles offices
            types = [:Still,:Kitchen, :Fishery,:Butchers, :Leatherworks,:Tanners,
                :Looms,:Clothiers, :Dyers,:Bowyers, nil,nil]
            types += [:Masons,:Carpenters, :Mechanics,:Farmers, :Craftsdwarfs,:Jewelers,
                :Ashery,:MetalsmithsForge, :WoodFurnace,:Smelter, :ManagersOffice,nil]

            [-1, 1].each { |dirx|
                prev_corx = corridor_center
                ocx = fx + dirx*3
                (1..6).each { |dx|
                    # segments of the big central horizontal corridor
                    cx = fx + dirx*(4*dx-1)
                    if dx <= 5
                        cor_x = Corridor.new(ocx, cx, fy-1, fy+1, fz, fz)
                        cor_x.accesspath = [prev_corx]
                        @corridors << cor_x
                    else
                        # last 2 workshops of the row (offices etc) get only a narrow/direct corridor
                        cor_x = Corridor.new(fx+dirx*3, cx, fy, fy, fz, fz)
                        cor_x.accesspath = [corridor_center]
                        @corridors << cor_x
                        cor_x = Corridor.new(cx, cx, fy-1, fy+1, fz, fz)
                        cor_x.accesspath = [@corridors.last]
                        @corridors << cor_x
                    end
                    prev_corx = cor_x
                    ocx = cx+dirx

                    @rooms << Room.new(:workshop, cx-1, cx+1, fy-5, fy-3, fz, [[cx, fy-2, fz]])
                    @rooms << Room.new(:workshop, cx-1, cx+1, fy+3, fy+5, fz, [[cx, fy+2, fz]])
                    @rooms[-2, 2].each { |r| r[:workshop] = types.shift ; r.accesspath = [cor_x] }
                }
            }
        end

        def setup_blueprint_stockpiles(fx, fy, fz, entr)
            corridor_center = Corridor.new(fx-2, fx+2, fy-1, fy+1, fz, fz) 
            corridor_center.accesspath = entr
            @corridors << corridor_center

            types = [:wood,:stone, :furniture,:goods, :gems,:weapons, :refuse,:corpses]
            types += [:food,:ammo, :cloth,:leather, :bars,:armor, :animals,:coins]

            # TODO side stairs to workshop level ?
            [-1, 1].each { |dirx|
                prev_corx = corridor_center
                ocx = fx + dirx*3
                (1..4).each { |dx|
                    # segments of the big central horizontal corridor
                    cx = fx + dirx*(8*dx-4)
                    cor_x = Corridor.new(ocx, cx+dirx, fy-1, fy+1, fz, fz)
                    cor_x.accesspath = [prev_corx]
                    @corridors << cor_x
                    prev_corx = cor_x
                    ocx = cx+2*dirx

                    @rooms << Room.new(:stockpile, cx-3, cx+3, fy-11, fy-3, fz, [[cx-1, fy-2, fz], [cx+1, fy-2, fz]])
                    @rooms << Room.new(:stockpile, cx-3, cx+3, fy+3, fy+11, fz, [[cx-1, fy+2, fz], [cx+1, fy+2, fz]])
                    @rooms[-2, 2].each { |r| r[:type] = types.shift ; r.accesspath = [cor_x] }
                }
            }
        end

        def setup_blueprint_utilities(fx, fy, fz, entr)
            corridor_center = Corridor.new(fx-2, fx+2, fy-1, fy+1, fz, fz) 
            corridor_center.accesspath = entr
            @corridors << corridor_center

            # TODO
            # dining room
            # infirmary
            # cemetary
            # well
            # military
            # farmplots?
        end

        def setup_blueprint_bedrooms(fx, fy, fz, entr)
            corridor_center = Corridor.new(fx-2, fx+2, fy-1, fy+1, fz, fz) 
            corridor_center.accesspath = entr
            @corridors << corridor_center

            [-1, 1].each { |dirx|
                prev_corx = corridor_center
                ocx = fx + dirx*3
                (1..3).each { |dx|
                    # segments of the big central horizontal corridor
                    cx = fx + dirx*(11*dx-4)
                    cor_x = Corridor.new(ocx, cx, fy-1, fy+1, fz, fz)
                    cor_x.accesspath = [prev_corx]
                    @corridors << cor_x
                    prev_corx = cor_x
                    ocx = cx+dirx

                    [-1, 1].each { |diry|
                        prev_cory = cor_x
                        ocy = fy + diry*2
                        (1..5).each { |dy|
                            cy = fy + diry*4*dy
                            cor_y = Corridor.new(cx, cx-dirx*1, ocy, cy, fz, fz)
                            cor_y.accesspath = [prev_cory]
                            @corridors << cor_y
                            prev_cory = cor_y
                            ocy = cy+diry

                            @rooms << Room.new(:bedroom, cx-dirx*5, cx-dirx*3, cy-1, cy+1, fz, [[cx-dirx*2, cy, fz]])
                            @rooms << Room.new(:bedroom, cx+dirx*2, cx+dirx*4, cy-1, cy+1, fz, [[cx+dirx*1, cy, fz]])
                            @rooms[-2, 2].each { |r| r.accesspath = [cor_y] }
                        }
                    }
                }
            }
        end

        class Corridor
            attr_accessor :x1, :x2, :y1, :y2, :z1, :z2, :accesspath, :status
            attr_accessor :misc
            def x; x1; end
            def y; y1; end
            def z; z1; end
            def w; x2-x1+1; end
            def h; y2-y1+1; end
            def h_z; z2-z1; end

            def [](k)
                @misc[k]
            end
            def []=(k, v)
                @misc[k] = v
            end

            def initialize(x1, x2, y1, y2, z1, z2)
                @misc = {}
                @status = :plan
                @accesspath = []
                x1, x2 = x2, x1 if x1 > x2
                y1, y2 = y2, y1 if y1 > y2
                z1, z2 = z2, z1 if z1 > z2
                @x1, @x2, @y1, @y2, @z1, @z2 = x1, x2, y1, y2, z1, z2
            end

            def dig
                return if @status != :plan
                @status = :dig
                accesspath.to_a.each { |ap| ap.dig if ap.status == :plan }
                (@x1..@x2).each { |x| (@y1..@y2).each { |y| (@z1..@z2).each { |z|
                    if t = df.map_tile_at(x, y, z)
                        dm = dig_mode(x, y, z)
                        t.dig dm if dm == :DownStair or t.shape == :WALL
                    end
                } } }
            end

            def dig_mode(x, y, z)
                wantup = wantdown = false
                wantup = true if z < z2
                wantdown = true if z > z1
                wantup = true if accesspath.find { |r|
                    r.x1 <= x and r.x2 >= x and r.y1 <= y and r.y2 >= y and r.z2 > z
                }
                wantdown = true if accesspath.find { |r|
                    r.x1 <= x and r.x2 >= x and r.y1 <= y and r.y2 >= y and r.z1 < z
                }
                if wantup
                    wantdown ? :UpDownStair : :UpStair
                else
                    wantdown ? :DownStair : :Default
                end
            end

            def dug?
                (@x1..@x2).each { |x| (@y1..@y2).each { |y| (@z1..@z2).each { |z|
                    if t = df.map_tile_at(x, y, z)
                        return false if t.shape == :WALL
                    end
                } } }
                @status = :dug
                true
            end
        end

        class Room < Corridor
            attr_accessor :doors, :type
            def initialize(type, x1, x2, y1, y2, z, doors=[])
                super(x1, x2, y1, y2, z, z)
                @type = type
                @doors = doors
            end

            def dig
                super
                @doors.each { |x, y, z|
                    if t = df.map_tile_at(x, y, z)
                        t.dig dig_mode(x, y, z)
                    end
                }
            end

            def dug?
                @doors.each { |x, y, z|
                    if t = df.map_tile_at(x, y, z)
                        return false if t.shape == :WALL
                    end
                }
                super
            end

            def dfbuilding
                df.building_find(self[:bld_id]) if self[:bld_id]
            end
        end
    end
end
