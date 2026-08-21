import Foundation

extension FootballDataAPIClient {
    func enrichedGoalScorers(_ scorers: FootballMatchGoalScorers) async -> FootballMatchGoalScorers {
        let home = await enrichedGoalScorers(scorers.home)
        let away = await enrichedGoalScorers(scorers.away)
        return FootballMatchGoalScorers(home: home, away: away)
    }

    func enrichedGoalScorers(_ scorers: [FootballMatchGoalScorer]) async -> [FootballMatchGoalScorer] {
        var enrichedScorers: [FootballMatchGoalScorer] = []
        enrichedScorers.reserveCapacity(scorers.count)

        for scorer in scorers {
            enrichedScorers.append(await enrichedGoalScorer(scorer))
        }

        return enrichedScorers
    }

    func enrichedGoalScorer(_ scorer: FootballMatchGoalScorer) async -> FootballMatchGoalScorer {
        if FootballFixtureFormatter.flagEmoji(for: scorer.countryName) != "🏳️" {
            return scorer
        }

        guard let athleteID = scorer.athleteID,
              let countryName = await fetchAthleteCountryName(athleteID: athleteID) else {
            return scorer
        }

        return FootballMatchGoalScorer(
            id: scorer.id,
            athleteID: scorer.athleteID,
            name: scorer.name,
            minute: scorer.minute,
            countryName: countryName,
            isOwnGoal: scorer.isOwnGoal,
            isPenalty: scorer.isPenalty
        )
    }

    func fetchAthleteCountryName(athleteID: String) async -> String? {
        let trimmedID = athleteID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }

        if let cached = athleteCountryCache.value(forKey: trimmedID) {
            return cached
        }
        if missingAthleteCountryIDs.contains(trimmedID) {
            return nil
        }

        guard let url = Self.athleteURL(athleteID: trimmedID) else {
            missingAthleteCountryIDs.insert(true, forKey: trimmedID)
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = Self.requestTimeout
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return nil
            }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 404 {
                    missingAthleteCountryIDs.insert(true, forKey: trimmedID)
                }
                return nil
            }

            let root = try Self.jsonDictionary(from: data)
            let countryName = Self.athleteCountryName(root)
                ?? (root["athlete"] as? [String: Any]).flatMap(Self.athleteCountryName)

            guard let countryName else {
                missingAthleteCountryIDs.insert(true, forKey: trimmedID)
                return nil
            }

            athleteCountryCache.insert(countryName, forKey: trimmedID)
            return countryName
        } catch {
            return nil
        }
    }
}
