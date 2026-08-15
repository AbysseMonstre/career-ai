// Data models mirroring the Career AI backend JSON.

class AppUser {
  final int id;
  final String email;
  final String name;
  final String role; // 'seeker' | 'recruiter'

  AppUser({required this.id, required this.email, required this.name, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'],
        email: j['email'],
        name: j['name'],
        role: j['role'],
      );

  bool get isSeeker => role == 'seeker';
  bool get isRecruiter => role == 'recruiter';
}

class MatchStats {
  final int score;
  final List<String> matchedSkills;
  final List<String> missingSkills;
  final int jobSkillCount;

  /// Null when the ad states no experience requirement — the score then
  /// ignores seniority entirely rather than guessing.
  final int? seniority;
  final int? requiredExperienceMonths;
  final int candidateExperienceMonths;

  MatchStats({
    required this.score,
    required this.matchedSkills,
    required this.missingSkills,
    required this.jobSkillCount,
    this.seniority,
    this.requiredExperienceMonths,
    this.candidateExperienceMonths = 0,
  });

  factory MatchStats.fromJson(Map<String, dynamic> j) => MatchStats(
        score: j['score'] ?? 0,
        matchedSkills: List<String>.from(j['matched_skills'] ?? []),
        missingSkills: List<String>.from(j['missing_skills'] ?? []),
        jobSkillCount: j['job_skill_count'] ?? 0,
        seniority: j['seniority'],
        requiredExperienceMonths: j['required_experience_months'],
        candidateExperienceMonths: j['candidate_experience_months'] ?? 0,
      );

  static String _months(int m) {
    if (m <= 0) return 'aucune';
    if (m < 12) return '$m mois';
    final y = m ~/ 12, rest = m % 12;
    final label = y > 1 ? '$y ans' : '1 an';
    return rest == 0 ? label : '$label $rest mois';
  }

  /// "Demandé : 3 ans · vous : 1 an 5 mois" — null when the ad is silent.
  String? get seniorityLabel {
    final req = requiredExperienceMonths;
    if (req == null) return null;
    final asked = req == 0 ? 'ouvert aux débutants' : 'demandé : ${_months(req)}';
    return '$asked · vous : ${_months(candidateExperienceMonths)}';
  }
}

class Job {
  final int id;
  final String source;
  final String title;
  final String company;
  final String location;
  final String url;
  final String description;
  final List<String> tags;
  final String salary;
  final MatchStats? match;
  final bool isAlternance;
  final String? contactEmail; // recruiter email found in the advert, if any
  bool liked; // mutable so the heart toggles instantly

  Job({
    required this.id,
    required this.source,
    required this.title,
    required this.company,
    required this.location,
    required this.url,
    required this.description,
    required this.tags,
    required this.salary,
    this.match,
    this.isAlternance = false,
    this.contactEmail,
    this.liked = false,
  });

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'],
        source: j['source'] ?? '',
        title: j['title'] ?? '',
        company: j['company'] ?? '',
        location: j['location'] ?? '',
        url: j['url'] ?? '',
        description: j['description'] ?? '',
        tags: List<String>.from(j['tags'] ?? []),
        salary: j['salary'] ?? '',
        match: j['match'] != null ? MatchStats.fromJson(j['match']) : null,
        isAlternance: j['is_alternance'] == true,
        contactEmail: (j['contact_email'] as String?)?.isNotEmpty == true
            ? j['contact_email'] as String
            : null,
        liked: j['liked'] == true,
      );
}

class Application {
  final int id;
  final String status; // auto_pending | validated | rejected | applied
  final int matchScore;
  final String title;
  final String company;
  final String location;
  final String url;
  final String source;
  final String createdAt;
  final String coverLetter;

  Application({
    required this.id,
    required this.status,
    required this.matchScore,
    required this.title,
    required this.company,
    required this.location,
    required this.url,
    required this.source,
    required this.createdAt,
    required this.coverLetter,
  });

  factory Application.fromJson(Map<String, dynamic> j) => Application(
        id: j['id'],
        status: j['status'] ?? 'auto_pending',
        matchScore: j['match_score'] ?? 0,
        title: j['title'] ?? '',
        company: j['company'] ?? '',
        location: j['location'] ?? '',
        url: j['url'] ?? '',
        source: j['source'] ?? '',
        createdAt: j['created_at'] ?? '',
        coverLetter: j['cover_letter'] ?? '',
      );
}

class Candidate {
  final int candidateId;
  final String name;
  final String email;
  final String title;
  final String location;
  final List<String> skills;
  final MatchStats match;
  final int applied; // number of offers this candidate has applied to
  // recruiter pipeline (mutable so the UI updates instantly)
  String status; // nouveau | preselectionne | entretien | retenu | refuse
  int rating; // 0-5
  String note;

  Candidate({
    required this.candidateId,
    required this.name,
    required this.email,
    required this.title,
    required this.location,
    required this.skills,
    required this.match,
    this.applied = 0,
    this.status = 'nouveau',
    this.rating = 0,
    this.note = '',
  });

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        candidateId: j['candidate_id'],
        name: j['name'] ?? '',
        email: j['email'] ?? '',
        title: j['title'] ?? '',
        location: j['location'] ?? '',
        skills: List<String>.from(j['skills'] ?? []),
        match: MatchStats.fromJson(j['match']),
        applied: j['applied'] ?? 0,
        status: j['status'] ?? 'nouveau',
        rating: j['rating'] ?? 0,
        note: j['note'] ?? '',
      );
}

class Interview {
  final int id;
  final String candidateName;
  final String company;
  final String scheduledAt; // ISO datetime string
  final String meetingType; // visio | phone | onsite
  final String link;
  final String location;
  final int durationMin;
  final String message;
  final String status; // proposed | accepted | declined

  Interview({
    required this.id,
    required this.candidateName,
    required this.company,
    required this.scheduledAt,
    required this.meetingType,
    required this.link,
    required this.location,
    required this.durationMin,
    required this.message,
    required this.status,
  });

  DateTime? get when => DateTime.tryParse(scheduledAt);

  factory Interview.fromJson(Map<String, dynamic> j) => Interview(
        id: j['id'] ?? 0,
        candidateName: j['candidate_name'] ?? j['candidateName'] ?? '',
        company: j['company'] ?? '',
        scheduledAt: j['scheduled_at'] ?? '',
        meetingType: (j['meeting_type'] ?? 'visio').toString(),
        link: j['teams_link'] ?? '',
        location: j['location'] ?? '',
        durationMin: (j['duration_min'] ?? 30) is int
            ? (j['duration_min'] ?? 30)
            : int.tryParse('${j['duration_min']}') ?? 30,
        message: j['message'] ?? '',
        status: j['status'] ?? 'proposed',
      );
}

class Achievement {
  final String id;
  final String label;
  final String emoji;
  final bool done;
  Achievement({required this.id, required this.label, required this.emoji, required this.done});
  factory Achievement.fromJson(Map<String, dynamic> j) => Achievement(
        id: j['id'] ?? '', label: j['label'] ?? '', emoji: j['emoji'] ?? '🏅',
        done: j['done'] == true,
      );
}

/// One job held by the candidate, as rebuilt from their CV.
class CvExperience {
  final String period, role, company, location, context;
  final int? durationMonths;
  final bool ongoing;
  final List<String> bullets;
  CvExperience({
    this.period = '', this.role = '', this.company = '', this.location = '',
    this.context = '', this.durationMonths, this.ongoing = false,
    this.bullets = const [],
  });
  factory CvExperience.fromJson(Map<String, dynamic> j) => CvExperience(
        period: j['period'] ?? '', role: j['role'] ?? '',
        company: j['company'] ?? '', location: j['location'] ?? '',
        context: j['context'] ?? '',
        durationMonths: j['duration_months'],
        ongoing: j['ongoing'] == true,
        bullets: List<String>.from(j['bullets'] ?? const []),
      );

  /// "6 mois", "1 an 5 mois" — empty when the CV gave no usable dates.
  String get durationLabel {
    final m = durationMonths;
    if (m == null || m <= 0) return '';
    if (m < 12) return '$m mois';
    final years = m ~/ 12, rest = m % 12;
    final y = years > 1 ? '$years ans' : '1 an';
    return rest == 0 ? y : '$y $rest mois';
  }
}

/// A dated line from the CV (diploma, certification).
class CvEntry {
  final String period, label;
  CvEntry({this.period = '', this.label = ''});
  factory CvEntry.fromJson(Map<String, dynamic> j) =>
      CvEntry(period: j['period'] ?? '', label: j['label'] ?? '');
}

/// A competency written by the candidate: "<label> : <detail>".
class CvSkill {
  final String label, detail;
  CvSkill({this.label = '', this.detail = ''});
  factory CvSkill.fromJson(Map<String, dynamic> j) =>
      CvSkill(label: j['label'] ?? '', detail: j['detail'] ?? '');
}

/// The CV rebuilt as sections. Any list may be empty when the PDF had no
/// recognisable section of that kind.
class CvStructure {
  final List<CvExperience> experiences;
  final List<CvEntry> education, certifications;
  final List<CvSkill> declaredSkills;
  final List<String> languages, sectionsFound;
  final int totalExperienceMonths;
  CvStructure({
    this.experiences = const [], this.education = const [],
    this.certifications = const [], this.declaredSkills = const [],
    this.languages = const [], this.sectionsFound = const [],
    this.totalExperienceMonths = 0,
  });

  bool get isEmpty =>
      experiences.isEmpty && education.isEmpty &&
      certifications.isEmpty && declaredSkills.isEmpty && languages.isEmpty;

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      ((v ?? const []) as List).map((e) => f(Map<String, dynamic>.from(e))).toList();

  factory CvStructure.fromJson(Map<String, dynamic> j) => CvStructure(
        experiences: _list(j['experiences'], CvExperience.fromJson),
        education: _list(j['education'], CvEntry.fromJson),
        certifications: _list(j['certifications'], CvEntry.fromJson),
        declaredSkills: _list(j['declared_skills'], CvSkill.fromJson),
        languages: List<String>.from(j['languages'] ?? const []),
        sectionsFound: List<String>.from(j['sections_found'] ?? const []),
        totalExperienceMonths: j['total_experience_months'] ?? 0,
      );

  /// "1 an 5 mois d'expérience" for the summary header.
  String get totalLabel {
    final m = totalExperienceMonths;
    if (m <= 0) return '';
    if (m < 12) return "$m mois d'expérience";
    final years = m ~/ 12, rest = m % 12;
    final y = years > 1 ? '$years ans' : '1 an';
    return rest == 0 ? "$y d'expérience" : "$y $rest mois d'expérience";
  }
}

class Mission {
  final String id, label, emoji;
  final int progress, goal, xp;
  final bool done;
  Mission({required this.id, required this.label, required this.emoji,
    required this.progress, required this.goal, required this.xp, required this.done});
  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
        id: j['id'] ?? '', label: j['label'] ?? '', emoji: j['emoji'] ?? '🎯',
        progress: j['progress'] ?? 0, goal: j['goal'] ?? 1, xp: j['xp'] ?? 0,
        done: j['done'] == true,
      );
}

class Gamification {
  final int completion, xp, level, xpInLevel, xpNext, unlocked, totalBadges;
  final List<Achievement> achievements;
  final List<Mission> missions;
  Gamification({
    this.completion = 0, this.xp = 0, this.level = 1, this.xpInLevel = 0,
    this.xpNext = 100, this.unlocked = 0, this.totalBadges = 0,
    this.achievements = const [], this.missions = const [],
  });
  factory Gamification.fromJson(Map<String, dynamic> j) => Gamification(
        completion: j['completion'] ?? 0,
        xp: j['xp'] ?? 0,
        level: j['level'] ?? 1,
        xpInLevel: j['xp_in_level'] ?? 0,
        xpNext: j['xp_next'] ?? 100,
        unlocked: j['unlocked'] ?? 0,
        totalBadges: j['total_badges'] ?? 0,
        achievements: ((j['achievements'] ?? []) as List).map((e) => Achievement.fromJson(e)).toList(),
        missions: ((j['missions'] ?? []) as List).map((e) => Mission.fromJson(e)).toList(),
      );
}

class SeekerDashboard {
  final String title;
  final String location;
  final List<String> skills;
  final int applied;
  final int validated;
  final int pending;
  final int rejected;
  final int totalApplications;
  final int avgMatchScore;
  final int jobsAvailable;
  final Gamification gamification;

  SeekerDashboard({
    required this.title,
    required this.location,
    required this.skills,
    required this.applied,
    required this.validated,
    required this.pending,
    required this.rejected,
    required this.totalApplications,
    required this.avgMatchScore,
    required this.jobsAvailable,
    Gamification? gamification,
  }) : gamification = gamification ?? Gamification();

  factory SeekerDashboard.fromJson(Map<String, dynamic> j) {
    final p = j['profile'] ?? {};
    final a = j['applications'] ?? {};
    return SeekerDashboard(
      title: p['title'] ?? '',
      location: p['location'] ?? '',
      skills: List<String>.from(p['skills'] ?? []),
      applied: a['applied'] ?? 0,
      validated: a['validated'] ?? 0,
      pending: a['pending'] ?? 0,
      rejected: a['rejected'] ?? 0,
      totalApplications: a['total'] ?? 0,
      avgMatchScore: j['avg_match_score'] ?? 0,
      jobsAvailable: j['jobs_available'] ?? 0,
      gamification: Gamification.fromJson(j['gamification'] ?? {}),
    );
  }
}

class RecruiterDashboard {
  final int talentPoolSize;
  final int myPostedJobs;
  final int applicationsReceived;
  final Gamification gamification;

  RecruiterDashboard({
    required this.talentPoolSize,
    required this.myPostedJobs,
    required this.applicationsReceived,
    Gamification? gamification,
  }) : gamification = gamification ?? Gamification();

  factory RecruiterDashboard.fromJson(Map<String, dynamic> j) => RecruiterDashboard(
        talentPoolSize: j['talent_pool_size'] ?? 0,
        myPostedJobs: j['my_posted_jobs'] ?? 0,
        applicationsReceived: j['applications_received'] ?? 0,
        gamification: Gamification.fromJson(j['gamification'] ?? {}),
      );
}
