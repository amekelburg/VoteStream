require 'vssc'
class VSSCLoader < BaseLoader
  
  def initialize(xml_source)
    @xml_source = xml_source
  end
  
  def load
    er = ::VSSC::Parser.parse(@xml_source)
    Election.transaction do
      election = Election.new(uid: er.object_id + '-vssc')
      election.held_on = er.date
      election.state = State.find_by(code: er.state_abbreviation)

      # election.statewide = false # what does this mean ??

      
      election.election_type = "general"
      
      
      locality = Locality.new(name: "Travis County - VSSC", 
                      locality_type: "County", 
                      state: election.state, 
                      uid: "tvcounty-vssc-test")
      
      Locality.where(uid: locality.uid).destroy_all
      
      # first load up all the districts
      #districts = []
      #precincts = []
      precinct_splits = {}                                
      er.gp_unit_collection.gp_unit.each do |gp_unit|
        if gp_unit.is_a?(VSSC::District)
          type = gp_unit.district_type
          type = "Other" if type.blank?
          d = District.new(name: gp_unit.name, district_type: type, uid: gp_unit.object_id)
          d.save!
          locality.districts << d
          gp_unit.gp_sub_unit_ref.each do |sub_gp_id|
            precinct_splits[sub_gp_id] ||= {:districts=>[], :precincts=>[]}
            precinct_splits[sub_gp_id][:districts] << d
          end
        else
          p = Precinct.new(uid: gp_unit.object_id, name: gp_unit.object_id)
          locality.precincts << p
          gp_unit.gp_sub_unit_ref.each do |sub_gp_id|
            precinct_splits[sub_gp_id] ||= {:districts=>[], :precincts=>[]}
            precinct_splits[sub_gp_id][:precincts] << p
          end
        end        
      end
      
      precinct_splits.each do |split, matched_gpus|
        matched_gpus[:districts].each do |d|
          puts d.name, matched_gpus[:precincts].count
          matched_gpus[:precincts].each do |p|
            d.precincts << p
          end
        end
      end
      
      er.party_collection.party.each_with_index do |p,i|
        name = p.name
        name = p.abbreviation if name.blank?
        locality.parties << Party.new(uid: p.object_id, name: name, sort_order: i, abbr: p.abbreviation)
      end

      offices = {}
      er.office_collection.office.each do |o|
        offices[o.object_id] = o
      end
      
      
      locality.save!
      
      
      er.election.first.tap do |e|
        candidates = {}
        e.candidate_collection.candidate.each do |c|
          candidates[c.object_id] = c
        end
        
        # where is this in hart??
        #   election.election_type = e.type
        e.contest_collection.contest.each do |c|
          if c.is_a?(VSSC::CandidateChoice)
            contest = Contest.new(uid: c.object_id,
              office: offices[c.office].name,
              sort_order: c.sequence_order)              
            contest.district = District.where(locality_id: locality.id, uid: c.contest_gp_scope).first
            c.ballot_selection.each_with_index do |candidate_sel, i|
              sel = candidates[candidate_sel.candidate.first] #TODO: can be multiple candidates in VSSC
              party = Party.where(uid: sel.party, locality_id: locality.id).first
              
              color = ColorScheme.candidate_pre_color(party.name)
              candidate = Candidate.new(uid: sel.object_id, 
                name: sel.ballot_name, 
                sort_order: sel.sequence_order, 
                party_id: party.id, 
                color: color)

              contest.candidates << candidate
            end
            contest.send(:set_district_type)
            raise contest.inspect.to_s + ' ' +  contest.district.inspect.to_s if contest.district_type != 'Other'
            
            locality.contests << contest
          elsif c.is_a?(VSSC::BallotMeasure)
            
          elsif c.is_a?(VSSC::StraightParty)
            # contest = Contest.new(uid: c.object_id,
            #   partisan: true,
            #   sort_order: c.sequence_order,)
            # contest.district = District.where(uid: c.contest_gp_scope).first
            # c.ballot_selection.each_with_index do |party_sel, i|
            #   party = Party.find_by_uid(party_sel)
            #
            #   color = ColorScheme.candidate_pre_color(party.name)
            #   candidate = Candidate.new(uid: party.uid,
            #     name: sel.ballot_name,
            #     sort_order: sel.sequence_order,
            #     party_id: party.id,
            #     color: color)
            #
            #   contest.candidates << candidate
            # end
            # locality.contests << contest
          end
        end
      end
      
      locality.save!
      
      Election.where(uid: election.uid).delete_all
      election.save!
      
    end
    
  end
  
  
end