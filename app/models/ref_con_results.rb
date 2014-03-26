class RefConResults

  CATEGORY_REFERENDUMS = 'Referendums'

  def initialize(options = {})
    @order_by_votes = (options[:candidate_ordering] || AppConfig[:candidate_ordering]) != 'sort_order'
  end

  def all_refcons(params)
    { federal: refcons_of_type('Federal', params),
      state:   refcons_of_type('State', params),
      mcd:     refcons_of_type('MCD', params),
      other:   refcons_of_type('Other', params) }
  end

  def refcons_of_type(district_type, params)
    contests = Contest.where(district_type: district_type, locality_id: params[:locality_id]).select("id, office as name, sort_order")
    refs     = Referendum.where(district_type: district_type, locality_id: params[:locality_id]).select("id, title as name, sort_order")
    [ contests, refs ].flatten.sort_by(&:sort_order).map { |i| { id: i.id, name: i.name, type: i.kind_of?(Contest) ? 'c' : 'r' } }
  end

  def region_refcons(params)
    list_to_refcons(refcons_in_region(params), params)
  end

  def contest_data(contest, params)
    pids       = precinct_ids_for_region(params)
    cids       = contest.candidate_ids
    candidates = contest.candidates
    results    = CandidateResult.where(candidate_id: cids)
    results = results.where(precinct_id: pids) unless pids.blank?

    candidate_votes = results.group('candidate_id').select("sum(votes) v, candidate_id").inject({}) do |m, cr|
      m[cr.candidate_id] = cr.v
      m
    end

    ordered = ordered_records(candidates, candidate_votes) do |c, votes, idx|
      { name: c.name, party: { name: c.party.name, abbr: c.party.abbr }, votes: votes, c: ColorScheme.candidate_color(c, idx) }
    end

    return {
      summary: {
        title:  contest.office,
        contest_type: contest.district_type,
        votes:  results.sum(:votes),
        rows:   ordered
      }
    }
  end

  def referendum_data(referendum, params)
    pids      = precinct_ids_for_region(params)
    brids     = referendum.ballot_response_ids
    responses = referendum.ballot_responses
    results   = BallotResponseResult.where(ballot_response_id: brids)
    results   = results.where(precinct_id: pids) unless pids.blank?

    response_votes = results.group('ballot_response_id').select("sum(votes) v, ballot_response_id").inject({}) do |m, br|
      m[br.ballot_response_id] = br.v
      m
    end

    ordered = ordered_records(responses, response_votes) do |b, votes, idx|
      { name: b.name, votes: votes, c: ColorScheme.ballot_response_color(b, idx) }
    end

    return {
      summary: {
        title:  referendum.title,
        subtitle: referendum.subtitle,
        text:   referendum.question,
        votes:  results.sum(:votes),
        rows:   ordered
      }
    }
  end

  def precinct_results(params)
    if cid = params[:contest_id]
      return contest_precinct_results(Contest.find(cid), params)
    elsif rid = params[:referendum_id]
      return referendum_precinct_results(Referendum.find(rid), params)
    else
      return {}
    end
  end

  # returns the results of polls for a given precinct (for API)
  def all_precinct_results(precinct, params)
    crs = precinct.contest_results.includes(:contest, :referendum)
    crs.map do |cr|
      if cr.contest_related?
        c = cr.contest

        results = cr.candidate_results.includes(:candidate).map do |res|
          { id:             res.uid,
            candidate_id:   res.candidate.uid,
            candidate_name: res.candidate.name,
            votes:          res.votes
          }
        end

        { id:                  cr.uid,
          certification:       cr.certification,
          contest_id:          c.uid,
          contest_name:        c.office,
          total_votes:         cr.total_votes,
          total_valid_votes:   cr.total_valid_votes,
          overvotes:           0,
          blank_votes:         0,
          ballot_line_results: results
        }
      elsif cr.referendum_related?
        r = cr.referendum

        results = cr.ballot_response_results.includes(:ballot_response).map do |res|
          { id:             res.uid,
            response_id:    res.ballot_response.uid,
            response_name:  res.ballot_response.name,
            votes:          res.votes
          }
        end

        { id:                  cr.uid,
          certification:       cr.certification,
          contest_id:          r.uid,
          contest_name:        r.title,
          total_votes:         cr.total_votes,
          total_valid_votes:   cr.total_valid_votes,
          overvotes:           0,
          blank_votes:         0,
          ballot_line_results: results
        }
      else
        nil
      end
    end.compact

    # filt = { district_id: precinct.district_ids }
    # contests = Contest.where(filt)
    # referendums = Referendum.where(filt)
    # refcons = [ contests, referendums ].flatten.compact
    #
    # refcons.inject([]) do |memo, refcon|
    #   if refcon.kind_of?(Contest)
    #     c = refcon
    #     cids = c.candidate_ids
    #
    #     candidate_query = Candidate.select("id, name, uid").where(id: cids)
    #     candidate_data = candidate_query.inject({}) do |m, r|
    #       m[r.id] = { uid: r.uid, name: r.name }
    #       m
    #     end
    #
    #     results = CandidateResult.where(candidate_id: cids, precinct_id: precinct.id)
    #     results = results.group('candidate_id').select("sum(votes) v, candidate_id").map do |cv|
    #       cdata = candidate_data[cv.candidate_id]
    #       { candidate_id: cdata[:uid], candidate_name: cdata[:name], votes: cv.v }
    #     end
    #
    #     memo << { contest_id: c.uid, results: results }
    #   else
    #     r = refcon
    #     brids = r.ballot_response_ids
    #
    #     ballot_response_uids = BallotResponse.select("id, uid").where(id: brids).inject({}) do |m, r|
    #       m[r.id] = r.uid
    #       m
    #     end
    #
    #     results = BallotResponseResult.where(ballot_response_id: brids, precinct_id: precinct.id)
    #     results = results.group('ballot_response_id').select("sum(votes) v, ballot_response_id").map do |bv|
    #       { ballot_response_id: ballot_response_uids[bv.ballot_response_id], votes: bv.v }
    #     end
    #
    #     memo << { referendum_id: r.uid, results: results }
    #   end
    #
    #   memo
    # end
  end

  private

  def contest_precinct_results(contest, params)
    precincts  = contest.precincts
    candidates = contest.candidates
    results    = CandidateResult.where(candidate_id: contest.candidate_ids)

    precinct_candidate_results = results.group_by(&:precinct_id).inject({}) do |memo, (pid, results)|
      memo[pid] = results
      memo
    end

    rating = CandidateResult.where(candidate_id: contest.candidate_ids).select("candidate_id, sum(votes) v").group('candidate_id').order("v desc").map(&:candidate_id)

    region_pids = precinct_ids_for_region(params)
    pmap = precincts.map do |p|
      pcr = precinct_candidate_results[p.id] || []
      candidate_votes = pcr.inject({}) do |memo, r|
        memo[r.candidate_id] = r.votes
        memo
      end

      ordered = ordered_records(candidates, candidate_votes) do |i, votes, idx|
        { id: i.id, votes: votes }
      end

      li = leader_info(pcr)
      candidate = li[:leader].try(:candidate)
      idx = rating.index(candidate.try(:id))

      { id:       p.id,
        inRegion: (region_pids && region_pids.include?(p.id)) || false,
        c:        ColorScheme.candidate_color(candidate, idx),
        adv:      li[:advantage],
        votes:    li[:total_votes],
        rows:     ordered[0, 2] }
    end

    return {
      items: candidates.map { |c| { id: c.id, name: c.name, party: { name: c.party.name, abbr: c.party.abbr }, c: ColorScheme.candidate_color(c, candidates.index(c)) } },
      precincts: pmap
    }
  end

  def referendum_precinct_results(referendum, params)
    precincts  = referendum.precincts
    responses  = referendum.ballot_responses
    ids        = referendum.ballot_response_ids
    results    = BallotResponseResult.where(ballot_response_id: ids)

    precinct_referendum_results = results.group_by(&:precinct_id).inject({}) do |memo, (pid, results)|
      memo[pid] = results
      memo
    end

    rating = ids

    region_pids = precinct_ids_for_region(params)
    pmap = precincts.map do |p|
      pcr = precinct_referendum_results[p.id] || []
      response_votes = pcr.inject({}) do |memo, r|
        memo[r.ballot_response_id] = r.votes
        memo
      end

      ordered = ordered_records(responses, response_votes) do |i, votes, idx|
        { id: i.id, votes: votes }
      end

      li = leader_info(pcr)
      ballot_response = li[:leader].try(:ballot_response)
      idx = rating.index(ballot_response.try(:id))

      { id:       p.id,
        inRegion: (region_pids && region_pids.include?(p.id)) || false,
        c:        ColorScheme.ballot_response_color(ballot_response, idx),
        adv:      li[:advantage],
        votes:    li[:total_votes],
        rows:     ordered[0, 2] }
    end

    return {
      items: responses.map { |r| { id: r.id, name: r.name, c: ColorScheme.ballot_response_color(r, responses.index(r)) } },
      precincts: pmap
    }
  end

  def leader_info(pcr)
    total_votes = pcr.sum(&:votes)

    if total_votes > 0
      pcr_s        = pcr.sort_by(&:votes).reverse
      leader       = pcr_s[0]
      leader_votes = leader.try(:votes).to_i
      runner_votes = pcr_s[1].try(:votes).to_i
      leader_perc  = leader_votes * 100 / total_votes
      runner_perc  = runner_votes * 100 / total_votes
      advantage    = leader_perc - runner_perc
    else
      leader       = nil
      advantage    = 0
    end

    return {
      total_votes: total_votes,
      leader: leader,
      advantage: advantage
    }
  end

  def ordered_records(items, items_votes, &block)
    unordered = items.map do |i|
      votes = items_votes[i.id].to_i
      { order: @order_by_votes ? -votes : i.sort_order, item: i }
    end

    ordered = unordered.sort_by { |cv| cv[:order] }.map { |cv| cv[:item] }

    idx = 0
    return ordered.map do |i|
      votes = items_votes[i.id].to_i
      data = block.call i, votes, idx
      idx += 1
      data
    end
  end

  def list_to_refcons(list, params)
    list.map do |rc|
      p = params.merge(no_precinct_results: true)
      if rc.kind_of?(Contest)
        data = contest_data(rc, p)
        data[:type] = 'c'
      else
        data = referendum_data(rc, p)
        data[:type] = 'r'
      end

      data[:id] = rc.id
      data
    end
  end

  # picks districts that are related to the given precinct or the precincts related to the given district
  def districts_for_region(params)
    if (pids = precinct_ids_for_region(params))
      DistrictsPrecinct.where(precinct_id: pids).uniq.pluck("district_id")
    else
      nil
    end
  end

  def precinct_ids_for_region(params)
    if (pid = params[:precinct_id]) || (did = params[:district_id])
      pid ? [ pid.to_i ] : DistrictsPrecinct.where(district_id: did).uniq.pluck("precinct_id")
    else
      nil
    end
  end

  def refcons_in_region(params)
    district_ids = districts_for_region(params)

    filt = {}
    filt[:district_id] = district_ids unless district_ids.blank?

    cat = params[:category]
    if cat.blank?
      if contest_id = params[:contest_id]
        contests = Contest.where(filt).where(id: contest_id)
      elsif referendum_id = params[:referendum_id]
        referendums = Referendum.where(filt).where(id: referendum_id)
      else
        contests = Contest.where(filt)
      end
    elsif cat == 'referenda'
      referendums = Referendum.where(filt)
    else
      contests = Contest.where(filt).where(district_type: cat)
      referendums = Referendum.where(filt).where(district_type: cat)
    end

    [ contests, referendums ].compact.flatten
  end

end
