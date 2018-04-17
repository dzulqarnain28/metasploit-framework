module NoteServlet

  def self.api_path
    '/api/v1/notes'
  end

  def self.api_path_with_id
    "#{NoteServlet.api_path}/?:id?"
  end

  def self.registered(app)
    app.get NoteServlet.api_path_with_id, &get_note
    app.post NoteServlet.api_path, &report_note
    app.put NoteServlet.api_path_with_id, &update_note
    app.delete NoteServlet.api_path, &delete_note
  end

  #######
  private
  #######

  def self.get_note
    lambda {
      begin
        opts = parse_json_request(request, false)
        data = get_db.notes(params.symbolize_keys)
        includes = [:host]
        set_json_response(data, includes)
      rescue Exception => e
        set_error_on_response(e)
      end
    }
  end

  def self.report_note
    lambda {
      begin
        job = lambda { |opts|
          get_db.report_note(opts)
        }
        exec_report_job(request, &job)
      rescue Exception => e
        set_error_on_response(e)
      end
    }
  end

  def self.update_note
    lambda {
      begin
        opts = parse_json_request(request, false)
        tmp_params = params.symbolize_keys
        opts[:id] = tmp_params[:id] if tmp_params[:id]
        data = get_db.update_note(opts)
        set_json_response(data)
      rescue Exception => e
        set_error_on_response(e)
      end
    }
  end

  def self.delete_note
    lambda {
      begin
        opts = parse_json_request(request, false)
        data = get_db.delete_note(opts)
        set_json_response(data)
      rescue Exception => e
        set_error_on_response(e)
      end
    }
  end

end