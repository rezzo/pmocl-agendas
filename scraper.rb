require 'rubygems'
require 'scraperwiki'
require 'nokogiri'
require 'open-uri'
require 'rest-client'
require 'pdf-reader'
require 'json'

# --------------------
# scrapable_classes.rb
# --------------------

module RestfulApiMethods

  @model =  ''
  @API_url = ''

  def format info
    info
  end

  def put record
    # RestClient.put @API_url + @model, record, {:content_type => :json}
  end

  def post record
    # RestClient.post @API_url + @model, record, {:content_type => :json}
  end
end

class StorageableInfo
  include RestfulApiMethods

  def initialize(location = '')
    @API_url = 'http://localhost:3000/'
    @location = location
  end

  def process
    doc_locations.each do |doc_location|
      begin
        doc = read doc_location
        # puts "<!---- raw doc ------>"
        # doc = doc.gsub /(\r?\n){3,}/, '\1\1'
        # puts doc
        # puts "<----- raw doc -----/>"
        info = get_info doc # obtain the juice

        info.delete_if { |k, v| v.nil? }
        if !info['bill_list'].empty? # if the document is valid then
          record = format info
          # puts '<!---- debug ' + @chamber + ' ------>'
          # puts record
          # puts '<----- debug ' + @chamber + ' -----/>'
          save record
        else
          puts "The current " + @chamber.to_s + " agenda hasn't relevant information."
        end
      rescue Exception=>e
        p e
      end
    end
  end

  def read location = @location
    # it would be better if instead we used
    # mimetype = `file -Ib #{path}`.gsub(/\n/,"")
    if location.class.name != 'String'
      doc = location
    elsif !location.scan(/pdf/).empty?
      doc_pdf = PDF::Reader.new(open(location))
      doc = ''
      doc_pdf.pages.each do |page|
        doc += page.text
      end
    else
      doc = open(location).read
    end
    doc
  end

  def doc_locations
    [@location]
  end

  def get_info doc
    doc
  end
end


# ---------------
# agendas_info.rb
# ---------------

class CongressTable < StorageableInfo

  def initialize()
    super()
    @model = 'agendas'
    @API_url = 'http://middleware.congresoabierto.cl/'
    @chamber = ''
  end

  def save record
    post record
  end

  def post record
    if ((ScraperWiki.select("* from data where `uid`='#{record['uid']}'").empty?) rescue true)
      RestClient.post @API_url + @model, {agenda: record}, {:content_type => :json}
      # Convert the array record['bill_list'] to a string (by converting to json)
      record['bill_list'] = JSON.dump(record['bill_list'])
      ScraperWiki.save_sqlite(['uid'], record)
      puts "Adds new record " + record['uid']
    else
      puts "Skipping already saved record " + record['uid']
    end
  end

  def format info
    record = {
      'uid' => info['legislature'] + '-' + info['session'],
      'date' => info['date'],
      'chamber' => @chamber,
      'legislature' => info['legislature'],
      'session' => info['session'],
      'bill_list' => info['bill_list'],
      'date_scraped' => Date.today.to_s
    }
  end

  def date_format date
    day = date [0]
    month = date [1]
    year = date [2]
    if day.length < 2 then day = "0" + day end
    months_num = {'enero' => '01', 'febrero' => '02', 'marzo' => '03', 'abril' => '04', 'mayo' => '05', 'junio' => '06', 'julio' => '07', 'agosto' => '08', 'septiembre' => '09', 'octubre' => '10', 'noviembre' => '11', 'diciembre' => '12'}

    date = [year, months_num[month], day]
    return date
  end

  def get_link(url, base_url, xpath)
    html = Nokogiri::HTML.parse(read(url), nil, 'utf-8')
    base_url + html.xpath(xpath).first['href']
  end
end

# ------------------------------------------------------------------------------------------------------------------------------------ SENADO -----------------------------
class CurrentHighChamberTable < CongressTable
  def initialize()
    super()
    @location = 'http://www.senado.cl/appsenado/index.php?mo=sesionessala&ac=doctosSesion&tipo=27'
    @base_url = 'http://www.senado.cl'
    @chamber = 'Senado'
  end

  # def process
  #   # puts 'processing'
  #   # puts doc_locations
  #   doc_locations.each do |doc_location|
  #     #begin
  #       doc = read doc_location
  #       info = get_info doc #obtain the data values
  #       record = format info
  #       puts "<!----- debug ----->"
  #       puts record
  #       puts "API url: " + @API_url.to_s
  #       puts "model  : " + @model.to_s
  #       puts "<----- debug -----/>"
  #       save record
  #     #rescue Exception=>e
  #     #end
  #   end
  # end

  def doc_locations
    html = Nokogiri::HTML(read(@location), nil, 'utf-8')
    doc_locations = Array.new

    doc_locations.push @base_url + html.xpath("//a[@class='citaciones']/@href").to_s.strip
    return doc_locations
  end

  def get_info doc
    info = Hash.new

    rx_bills = /Bolet(.*\d+-\d+)*/
    bills = doc.scan(rx_bills)

    bill_list = []
    rx_bill_num = /(\d{0,3})[^0-9]*(\d{0,3})[^0-9]*(\d{1,3})[^0-9]*(-)[^0-9]*(\d{2})/
    bills.each do |bill|
      bill.first.scan(rx_bill_num).each do |bill_num_array|
        bill_num = (bill_num_array).join('')
        bill_list.push(bill_num)
      end
    end

    # Get date
    rx_date = /(\d{1,2}) (?:de ){0,1}(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre) (?:de ){0,1}(\d{4})/
    date_sp = doc.scan(rx_date).first
    if !date_sp.nil? then date = date_format(date_sp).join('-') end

    # Get legislature
    rx_legislature = /LEGISLATURA\sN\W+.(\d{3})/
    legislature = doc.scan(rx_legislature).flatten.first

    # Get session
    rx_session = /Sesi\Wn+.(\d{1,3})/
    session = doc.scan(rx_session).flatten.first

    return {'bill_list' => bill_list, 'date' => date, 'legislature' => legislature, 'session' => session}
  end
end

# ------------------------------------------------------------------------------------------------------------------------------------ CAMARA -----------------------------
class CurrentLowChamberTable < CongressTable

  def initialize()
    super()
    @location = 'http://www.camara.cl/trabajamos/sala_documentos.aspx?prmTIPO=TABLA'
    @chamber = 'C.Diputados'
    @session_base_url = 'http://www.camara.cl/trabajamos/'
    @table_base_url = 'http://www.camara.cl'
    @session_xpath = '//*[@id="detail"]/table/tbody/tr[1]/td[2]/a'
    @table_xpath = '//*[@id="detail"]/table/tbody/tr[1]/td/a'
  end

  def doc_locations
    doc_locations_array = Array.new
    # session_url = get_link(@location, @session_base_url, @session_xpath)
    table_url = get_link(@location, @table_base_url, @table_xpath)
    puts "<!---- table_url ----->"
    table_url = "http://www.camara.cl/pdf.aspx?prmID=10374&prmTIPO=TEXTOSESION"         # porque la ultima vale guano, asi que uso una tabla "valida"
    puts table_url
    puts "<----- table_url ----/>"
    doc_locations_array.push(table_url)
    # get all with doc.xpath('//*[@id="detail"]/table/tbody/tr[(position()>0)]/td[2]/a/@href').each do |tr|
  end

  def get_info doc
    rx_bills = /Bolet(.*\d+-\d+)*/
    bills = doc.scan(rx_bills)
    
    bill_list = []
    rx_bill_num = /(\d{0,3})[^0-9]*(\d{0,3})[^0-9]*(\d{1,3})[^0-9]*(-)[^0-9]*(\d{2})/
    bills.each do |bill|
      bill.first.scan(rx_bill_num).each do |bill_num_array|
        bill_num = (bill_num_array).join('')
        bill_list.push(bill_num)
      end
    end

    rx_1 = /^\*{3}(.+)$/ # atrapa todo el txt ***
    rx_2 = /Bolet.n\SN\s+.(\d+-\d+)*.\n\n\*{3}(.+)/ # atrapa billid + 1er txt ***


    # get date
    rx_date = /(\d{1,2}) (?:de ){0,1}(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre) (?:de ){0,1}(\d{4})/
    date_sp = doc.scan(rx_date).first
    if !date_sp.nil? then date = date_format(date_sp).join('-') end

    # get legislature
    rx_legislature = /(\d{3}).+LEGISLATURA/
    legislature = doc.scan(rx_legislature).flatten.first

    # get session
    rx_session = /Sesi.+?(\d{1,3})/
    session = doc.scan(rx_session).flatten.first

    return {'bill_list' => bill_list, 'date' => date, 'legislature' => legislature, 'session' => session}
  end
end

# class BillCategory < StorageableInfo

#   def initialize
#     super()
#     @location = 'bill_categories'
#     @bills_location = 'bills'
#     @match_info_location = 'categories'
#     @model = 'bills'

#     @bills = parse(read(@bills_location))
#     @categorized_bills = parse(read(@match_info_location))
#   end

#   def save record
#     post record
#   end

#   def doc_locations
#     parse(read(@location))
#   end

#   def parse doc
#     doc_hash = {}
#     doc.split(/\n/).each do |pair|
#       key, val = pair.split(/\t/)
#       if doc_hash.has_key?(key)
#         doc_hash[key].push(val)
#       else
#         doc_hash.store(key, [val])
#       end
#     end
#     doc_hash
#   end

#   def get_info doc
#     bill, cat_ids = doc
#     cat_array = []
#     cat_ids.each do |cat_id|
#       cat_val = @categorized_bills[cat_id]
#       cat_array.push(cat_val)
#     end
#     [bill, cat_array]
#   end

#   def format info
#     puts 'in format info'
#     bill, categories = info
#     record = {
#       'uid' => @bills[bill].first,
#       'matters' => categories.join('|')
#     }
#   end
# end


# -----------------
# agendas_runner.rb
# -----------------

if !(defined? Test::Unit::TestCase)
  CurrentHighChamberTable.new.process
  CurrentLowChamberTable.new.process
end
