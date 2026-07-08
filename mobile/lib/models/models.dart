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

  MatchStats({
    required this.score,
    required this.matchedSkills,
    required this.missingSkills,
    required this.jobSkillCount,
  });

  factory MatchStats.fromJson(Map<String, dynamic> j) => MatchStats(
        score: j['score'] ?? 0,
        matchedSkills: List<String>.from(j['matched_skills'] ?? []),
        missingSkills: List<String>.from(j['missing_skills'] ?? []),
        jobSkillCount: j['job_skill_count'] ?? 0,
      );
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

  Candidate({
    required this.candidateId,
    required this.name,
    required this.email,
    required this.title,
    required this.location,
    required this.skills,
    required this.match,
  });

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        candidateId: j['candidate_id'],
        name: j['name'] ?? '',
        email: j['email'] ?? '',
        title: j['title'] ?? '',
        location: j['location'] ?? '',
        skills: List<String>.from(j['skills'] ?? []),
        match: MatchStats.fromJson(j['match']),
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
  });

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
    );
  }
}

class RecruiterDashboard {
  final int talentPoolSize;
  final int myPostedJobs;
  final int applicationsReceived;

  RecruiterDashboard({
    required this.talentPoolSize,
    required this.myPostedJobs,
    required this.applicationsReceived,
  });

  factory RecruiterDashboard.fromJson(Map<String, dynamic> j) => RecruiterDashboard(
        talentPoolSize: j['talent_pool_size'] ?? 0,
        myPostedJobs: j['my_posted_jobs'] ?? 0,
        applicationsReceived: j['applications_received'] ?? 0,
      );
}
