require 'ncurses'

class NCursesUI
  attr_accessor :logger

  def initialize cloud
    @cloud = cloud
    @state = :running
    @frac = 0
    @title = "None"
    @op = " "
    @time = 0
    @timeleft = 0
    @playlist = []
  end

  def run
    begin
      stdscr = Ncurses.initscr
      Ncurses.start_color
      Colors.init
      Ncurses.keypad stdscr, true
      Ncurses.nonl
      Ncurses.raw
      Ncurses.cbreak
      Ncurses.noecho
      Ncurses.curs_set 0
      Ncurses::halfdelay 5
      @p = NProgress.new @stdscr, 0, 0, :cyan, :blue
      @l = NPlaylist.new @stdscr, 4, 0, :cyan, :white, :blue, 0, 0, @playlist
      @l.active = 0
      while(@state != :close)
        ch = Ncurses.getch
        #Nutils.print stdscr, 3, 0, "Test %s" % [ch], :red
        case ch
        when Ncurses::KEY_RESIZE
          @p.resize
          @l.resize
        when 110, 78, Ncurses::KEY_DOWN
          @cloud.nextTrack
        when 112, 80, Ncurses::KEY_UP
          @cloud.prevTrack
        when 113, 81
          @cloud.quit
        when 61, 43
          @cloud.volumeUp
        when 45, 95
          @cloud.volumeDown
        when 109, 77
          @cloud.toggleMute
        when 32
          @cloud.pause
        when 115
          @cloud.save
        end

        if @error
          Nutils.print stdscr, 3, 0, "Error: #{@error}", :red
        else
          tr = " %s " % [Nutils.timestr(@timetotal)]
          t = " %-#{Ncurses.COLS-tr.size-1}s%s" % [Nutils.timestr(@time), tr]
          @p.value = @frac
          @p.text = t
          @p.refresh
        end
        Nutils.print stdscr, 1, 0, "#{@op} #{@title}", :cyan, :black
        Nutils.print stdscr, 2, 0, "  by #{@username}", :cyan, :black
        @l.refresh
        Ncurses.refresh
      end
    rescue => ex
    ensure
      @l.close if @l
      @p.close if @p
      Ncurses.echo
      Ncurses.nocbreak
      Ncurses.nl
      Ncurses.endwin
      puts ex.inspect if ex
      puts ex.backtrace if ex
      #Colors.debug
    end
  end

  def cloud_update(arg)
    case arg[:state]
    when :load
      @playlist |= arg[:tracks]
      @l.list = @playlist if @l
    when :shuffle
      @playlist = arg[:tracks]
      @l.list = @playlist if @l
    when :next, :previous
      pos = arg[:position]
      @l.active = pos if @l
    end
  end

  def player_update(arg)
    case arg[:state]
    when :load
      track = arg[:track]
      if track.nil?
        @error = "Nothing found!"
      else
        @error = nil
        @title = track["title"]
        @username = track["user"]["username"]
        @timetotal = track["duration"]
        @error = track[:error] if track[:error]
      end
    when :info
      frame = arg[:frame].to_f
      frames = frame + arg[:frameleft]
      @frac = frame/frames
      @time = arg[:time].to_i
    when :pause
      @op = "\u2161"
    when :resume, :play
      @op = "\u25B6"
    when :stop
      @op = "\u25FC"
    when :error
      @error = arg[:error]
    end
  end

  def close
    @state = :close
  end
end

class Nutils
  def self.print(scr, row, col, text, fg=nil, bg=nil, width = (Ncurses.COLS))
    width = [Ncurses.COLS, col+width].min - col
    t = "%-#{width}s" % [scroll(text, width)]
    Ncurses.wattron(scr, Colors.map(fg, bg)) if fg
    Ncurses.mvwprintw scr, row, col, t
    Ncurses.wattroff(scr, Colors.map(fg, bg)) if fg
  end

  def self.scroll(text, width, offset=0)
    return unless text
    ellipsis = "*"
    t = text
    if t.size+offset > width
      t = t[offset..(width-ellipsis.size-1)] << ellipsis
    end
    t
  end

  def self.timestr(sec)
    sec = sec.to_i
    "%02d:%02d" % [sec/60, sec%60]
  end

end

class Colors
  $map = {}
  $counter = 0
  def self.init

    colors = [:black, :white, :red, :green, :yellow, :blue, :magenta, :cyan]
    self.add :white, :black
  end

  def self.map(fg, bg = nil)
    pair = [fg, bg]
    unless $map.has_key? pair
      self.add fg, bg
    end
    $map[pair]
  end

  def self.add(fg, bg)
    Ncurses.init_pair $counter, ncg(fg), ncg(bg)
    pair = [fg, bg]
    $map[pair] = Ncurses.COLOR_PAIR($counter)
    $counter += 1
  end

  def self.debug
    puts "map: #{$map}"
  end
  # get ncurses color constant
  def self.ncg(color)
    color = :black unless color
    Ncurses.const_get "COLOR_#{color.upcase}"
  end
end

class NProgress
  attr_reader :value
  attr_accessor :text
  def initialize scr, row, col, fg, bg, width=0, value = 0, text = ""
    @width = width
    @bg = bg
    @fg = fg
    @row = row
    @col = col
    @winfg = Ncurses.newwin 1, 1, @row, @col
    @winbg = Ncurses.newwin 1, width(), @row, @col
    @value = value
    @text = text
    refresh
  end

  def width
    [@col + @width, Ncurses.COLS].min - @col
  end

  def value=(val)
    @value = val
    Ncurses.wresize @winfg, 1, fgw if fgw > 0
  end

  def refresh
    Ncurses.wbkgd @winbg, Colors.map(@fg, @bg)
    Ncurses.wbkgd @winfg, Colors.map(@bg, @fg) if fgw > 0
    Nutils.print @winbg, 0, 0, @text
    Nutils.print @winfg, 0, 0, @text if fgw > 0
    Ncurses.wrefresh @winbg
    Ncurses.wrefresh @winfg if fgw > 0
  end
  
  def resize
  end

  def close
    Ncurses.delwin @winbg
    Ncurses.delwin @winfg
  end

  private
  def fgw
    w = width() == 0 ? Ncurses.COLS - @col : width()
    (w * @value).floor
  end
end

class NPlaylist
  attr_writer :list
  def initialize scr, row, col, fg, afg, bg, w, h, l
    @list = l
    @row = row
    @col = col
    @width = w
    @height = h
    @bg = bg
    @fg = fg
    @afg = afg
    @apos = -1
    @win = Ncurses.newwin height, width, @row, @col
    @dirty = true
    refresh
  end

  def width
    w = [@col + @width, Ncurses.COLS].min - @col
    if w == 0
      Ncurses.COLS - @col
    else
      w
    end
  end

  def height
    h = [@row + @height, Ncurses.LINES].min - @row
    if h == 0
      Ncurses.LINES - @row
    else
      h
    end
  end

  def active=(pos)
    @apos = pos
    @dirty = true
  end

  def resize
    Ncurses.wresize @win, height, width
    @dirty = true
  end

  def refresh
    return unless @dirty
    Ncurses.wbkgd @win, Colors.map(@fg, @bg)
    Ncurses.box @win, 0, 0
    if !@list.is_a?(Array) || @list.empty?
      Nutils.print @win, 1, 2, "Empty playlist", nil, nil, width - 3
    else
      r = 1
      size = height - 2
      offset = ([[size/2.0, @apos].max, [@list.size, size].max-(size/2.0)].min - size/2.0).ceil
      wr = 8
      wl = width - 3 - wr
      @list[offset..@list.size].each do |t|
        tl = t["title"]
        if @apos == r - 1 + offset
          tl = ">#{tl}"
          colfg = @afg
        else
          tl = " #{tl}"
          colfg = @fg
        end
        tr = "[%6s]" % Nutils.timestr(t["duration"]) 
        Nutils.print @win, r, 1, tl, colfg, @bg, wl+1
        Nutils.print @win, r, 2+wl, tr, colfg, @bg, wr
        r += 1
        if(r >= height - 1)
          # print arrow down
          break
        end
      end
    end
    Ncurses.wrefresh @win
    @dirty = false
  end

  def close
    Ncurses.delwin @win
  end
end
