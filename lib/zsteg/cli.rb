require 'optparse'

module ZSteg
  class CLI
    DEFAULT_ACTIONS = %w'check'

    def initialize argv = ARGV
      @argv = argv
    end

    def run
      @actions = []
      @options = {
        :verbose => 0,
        :limit => Checker::DEFAULT_LIMIT,
        :order => Checker::DEFAULT_ORDER
      }
      optparser = OptionParser.new do |opts|
        opts.banner = "Usage: zsteg [options] filename.png [param_string]"
        opts.separator ""

        opts.on("-c", "--channels X", /[rgba,1-8]+/,
                "channels (R/G/B/A) or any combination, comma separated",
                "valid values: r,g,b,a,rg,bgr,rgba,r3g2b3,..."
        ){ |x| @options[:channels] = x.split(',') }

        opts.on("-l", "--limit N", Integer,
                "limit bytes checked, 0 = no limit (default: #{@options[:limit]})"
        ){ |n| @options[:limit] = n }

        opts.on("-b", "--bits N", /[\d,-]+/,
                "number of bits (1..8), single value or '1,3,5' or '1-8'") do |n|
          if n['-']
            @options[:bits] = Range.new(*n.split('-').map(&:to_i)).to_a
          else
            @options[:bits] = n.split(',').map(&:to_i)
          end
        end

        opts.on "--lsb", "least significant BIT comes first" do
          @options[:bit_order] = :lsb
        end
        opts.on "--msb", "most significant BIT comes first" do
          @options[:bit_order] = :msb
        end

        opts.on "-P", "--prime", "analyze/extract only prime bytes/pixels" do
          @options[:prime] = true
        end
#        opts.on "--pixel-align", "pixel-align hidden data (EasyBMP)" do
#          @options[:pixel_align] = true
#        end

        opts.on "-a", "--all", "try all known methods" do
          @options[:prime] = :all
          @options[:order] = :all
        end

        opts.on("-o", "--order X", /all|auto|[bxy,]+/i,
                "pixel iteration order (default: '#{@options[:order]}')",
                "valid values: ALL,xy,yx,XY,YX,xY,Xy,bY,...",
        ){ |x| @options[:order] = x.split(',') }

        opts.on "-E", "--extract NAME", "extract specified payload, NAME is like '1b,rgb,lsb'" do |x|
          @actions << [:extract, x]
        end

        opts.separator ""
        opts.on "-v", "--verbose", "Run verbosely (can be used multiple times)" do |v|
          @options[:verbose] += 1
        end
        opts.on "-q", "--quiet", "Silent any warnings (can be used multiple times)" do |v|
          @options[:verbose] -= 1
        end
        opts.on "-C", "--[no-]color", "Force (or disable) color output (default: auto)" do |x|
          Sickill::Rainbow.enabled = x
        end
        opts.separator "\nPARAMS SHORTCUT\n"+
          "\tzsteg fname.png 2b,b,lsb,xy  ==>  --bits 2 --channel b --lsb --order xy"
      end

      if (argv = optparser.parse(@argv)).empty?
        puts optparser.help
        return
      end

      @actions = DEFAULT_ACTIONS if @actions.empty?

      argv.each do |arg|
        if arg[','] && !File.exist?(arg)
          @options.merge!(decode_param_string(arg))
          argv.delete arg
        end
      end

      argv.each_with_index do |fname,idx|
        if argv.size > 1 && @options[:verbose] >= 0
          puts if idx > 0
          puts "[.] #{fname}".green
        end
        next unless @img=load_image(@fname=fname)

        @actions.each do |action|
          if action.is_a?(Array)
            self.send(*action) if self.respond_to?(action.first)
          else
            self.send(action) if self.respond_to?(action)
          end
        end
      end
    rescue Errno::EPIPE
      # output interrupt, f.ex. when piping output to a 'head' command
      # prevents a 'Broken pipe - <STDOUT> (Errno::EPIPE)' message
    end

    def load_image fname
      if File.directory?(fname)
        puts "[?] #{fname} is a directory".yellow
      else
        ZPNG::Image.load(fname)
      end
    rescue ZPNG::Exception, Errno::ENOENT
      puts "[!] #{$!.inspect}".red
    end

    def decode_param_string s
      h = {}
      s.split(',').each do |x|
        case x
        when 'lsb'
          h[:bit_order] = :lsb
        when 'msb'
          h[:bit_order] = :msb
        when /(\d)b/
          h[:bits] = $1.to_i
        when /\A[rgba]+\Z/
          h[:channels] = [x]
        when /\Axy|yx|yb|by\Z/i
          h[:order] = x
        when 'prime'
          h[:prime] = true
        else
          raise "uknown param #{x.inspect}"
        end
      end
      h
    end

    ###########################################################################
    # actions

    def check
      Checker.new(@img, @options).check
    end

    def extract name
      if ['extradata', 'data after IEND'].include?(name)
        print @img.extradata
        return
      end

      h = decode_param_string name
      h[:limit] = @options[:limit] if @options[:limit] != Checker::DEFAULT_LIMIT
      print Extractor.new(@img, @options).extract(h)
    end

  end
end
