require 'metasploit/framework/data_service/remote/http/response_data_helper'

module RemoteLootDataService
  include ResponseDataHelper

  LOOT_API_PATH = '/api/1/msf/loot'
  LOOT_MDM_CLASS = 'Mdm::Loot'

  def loot(opts = {})
    # TODO: Add an option to toggle whether the file data is returned or not
    loots = json_to_mdm_object(self.get_data(LOOT_API_PATH, opts), LOOT_MDM_CLASS, [])
    # Save a local copy of the file
    loots.each do |loot|
      if loot.data
        local_path = File.join(Msf::Config.loot_directory, File.basename(loot.path))
        loot.path = process_file(loot.data, local_path)
      end
    end
    loots
  end

  def report_loot(opts)
    self.post_data_async(LOOT_API_PATH, opts)
  end

  def find_or_create_loot(opts)
    json_to_mdm_object(self.get_data(LOOT_API_PATH, opts), LOOT_MDM_CLASS, [])
  end

  def report_loots(loot)
    self.post_data(LOOT_API_PATH, loot)
  end
end