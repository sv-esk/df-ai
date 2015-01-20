class DwarfAI
    class RandomEmbark
        attr_accessor :ai
        def initialize(ai)
            @ai = ai
            df.onupdate_register_once('df-ai random_embark') { update } if $AI_RANDOM_EMBARK
        end

        def startup
            # do nothing
        end

        def onupdate_register
            # do nothing
        end

        def onupdate_unregister
            if $AI_RANDOM_EMBARK
                ai.timeout_sameview(60) do
                    df.curview.feed_keys(:CLOSE_MEGA_ANNOUNCEMENT)

                    # reset
                    $dwarfAI = DwarfAI.new

                    df.onupdate_register_once('df-ai restart') {
                        if df.curview._raw_rtti_classname == 'viewscreen_dwarfmodest'
                            begin
                                $dwarfAI.onupdate_register
                                $dwarfAI.startup
                                df.curview.feed_keys(:D_PAUSE) if df.pause_state
                            rescue Exception
                                puts $!, $!.backtrace
                            end
                            true
                        end
                    }
                end
            end
        end

        def update
            view = df.curview
            return if not view or view.breakdown_level != :NONE
            case view
            when DFHack::ViewscreenTitlest
                case view.sel_subpage
                when :None
                    if $AI_RANDOM_EMBARK_WORLD and view.menu_line_id.include?(1)
                        view.sel_menu_line = view.menu_line_id.index(1)
                        view.feed_keys(:SELECT)
                    else
                        view.sel_menu_line = view.menu_line_id.index(2)
                        view.feed_keys(:SELECT)
                    end
                when :StartSelectWorld
                    if not $AI_RANDOM_EMBARK_WORLD
                        view.feed_keys(:LEAVESCREEN)
                        return
                    end

                    # XXX the memory structures are wrong. Revisit this when they get fixed.
                    l = view.start_savegames.length
                    save = view.continue_savegames.to_a[-l, l].index($AI_RANDOM_EMBARK_WORLD)
                    if save
                        view.sel_submenu_line = save
                        view.feed_keys(:SELECT)
                    else
                        $AI_RANDOM_EMBARK_WORLD = nil
                        view.feed_keys(:LEAVESCREEN)
                    end
                when :StartSelectMode
                    if view.submenu_line_id.include?(0)
                        view.sel_menu_line = view.submenu_line_id.index(0)
                        view.feed_keys(:SELECT)
                    else
                        $AI_RANDOM_EMBARK_WORLD = nil
                        view.feed_keys(:LEAVESCREEN)
                    end
                end
            when DFHack::ViewscreenNewRegionst
                return if $AI_RANDOM_EMBARK_WORLD

                if not view.unk_33.empty?
                    view.feed_keys(:LEAVESCREEN)
                elsif df.world.worldgen_status.state == 0
                    view.feed_keys(:MENU_CONFIRM)
                elsif df.world.worldgen_status.state == 10
                    $AI_RANDOM_EMBARK_WORLD = df.world.cur_savegame.save_dir
                    view.feed_keys(:SELECT)
                end
            when DFHack::ViewscreenChooseStartSitest
                if view.finder.finder_state == -1
                    view.feed_keys(:SETUP_FIND)
                    view.finder.options[:DimensionX] = 3
                    view.finder.options[:DimensionY] = 2
                    view.finder.options[:Aquifer] = 0
                    view.finder.options[:River] = 1
                    view.feed_keys(:SELECT)
                elsif view.finder.search_x == -1
                    if view.in_embark_salt # XXX
                        view.feed_keys(:SELECT)
                    elsif view.finder.finder_state == 2
                        view.feed_keys(:LEAVESCREEN)
                        view.feed_keys(:SETUP_EMBARK)
                    else
                        # no good embarks
                        $AI_RANDOM_EMBARK_WORLD = nil
                        view.breakdown_level = :TOFIRST
                    end
                end
            when DFHack::ViewscreenSetupdwarfgamest
                view.feed_keys(:SELECT)
                # TODO custom embark loadout
            when DFHack::ViewscreenTextviewerst
                ai.timeout_sameview do
                    df.curview.feed_keys(:LEAVESCREEN)
                    df.ui_area_map_width = 3
                    df.ui_menu_width = 3
                end
                return true
            end
            false
        end

        def status
            ""
        end

        def serialize
            {}
        end
    end
end

# vim: et:sw=4:ts=4
