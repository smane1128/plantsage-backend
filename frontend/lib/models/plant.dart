class PlantIdentification {
  final String plantName;
  final String scientificName;
  final String plantFamily;
  final String plantType;
  final String origin;
  final int confidenceLevel;
  final String description;

  PlantIdentification({
    required this.plantName,
    required this.scientificName,
    required this.plantFamily,
    required this.plantType,
    required this.origin,
    required this.confidenceLevel,
    required this.description,
  });

  factory PlantIdentification.fromJson(Map<String, dynamic> j) => PlantIdentification(
        plantName: j['plant_name'] ?? 'Unknown',
        scientificName: j['scientific_name'] ?? '',
        plantFamily: j['plant_family'] ?? '',
        plantType: j['plant_type'] ?? '',
        origin: j['origin'] ?? '',
        confidenceLevel: (j['confidence_level'] ?? 0) is int
            ? j['confidence_level'] ?? 0
            : int.tryParse(j['confidence_level'].toString()) ?? 0,
        description: j['description'] ?? '',
      );
}

class PlantSuitability {
  final String climate;
  final String temperatureRange;
  final String sunlight;
  final String humidity;
  final String windTolerance;

  PlantSuitability({
    required this.climate,
    required this.temperatureRange,
    required this.sunlight,
    required this.humidity,
    required this.windTolerance,
  });

  factory PlantSuitability.fromJson(Map<String, dynamic> j) => PlantSuitability(
        climate: j['climate'] ?? '',
        temperatureRange: j['temperature_range'] ?? '',
        sunlight: j['sunlight'] ?? '',
        humidity: j['humidity'] ?? '',
        windTolerance: j['wind_tolerance'] ?? '',
      );
}

class PlantGrowing {
  final String soilType;
  final String soilPh;
  final String watering;
  final String fertilizer;
  final String mulching;
  final String potOrGround;
  final String drainage;

  PlantGrowing({
    required this.soilType,
    required this.soilPh,
    required this.watering,
    required this.fertilizer,
    required this.mulching,
    required this.potOrGround,
    required this.drainage,
  });

  factory PlantGrowing.fromJson(Map<String, dynamic> j) => PlantGrowing(
        soilType: j['soil_type'] ?? '',
        soilPh: j['soil_ph'] ?? '',
        watering: j['watering'] ?? '',
        fertilizer: j['fertilizer'] ?? '',
        mulching: j['mulching'] ?? '',
        potOrGround: j['pot_or_ground'] ?? '',
        drainage: j['drainage'] ?? '',
      );
}

class PlantSpace {
  final String matureHeight;
  final String matureWidth;
  final String growthRate;
  final String rootSpread;
  final String spacing;

  PlantSpace({
    required this.matureHeight,
    required this.matureWidth,
    required this.growthRate,
    required this.rootSpread,
    required this.spacing,
  });

  factory PlantSpace.fromJson(Map<String, dynamic> j) => PlantSpace(
        matureHeight: j['mature_height'] ?? '',
        matureWidth: j['mature_width'] ?? '',
        growthRate: j['growth_rate'] ?? '',
        rootSpread: j['root_spread'] ?? '',
        spacing: j['spacing'] ?? '',
      );
}

class PlantMaintenance {
  final String pruning;
  final String pestSusceptibility;
  final String diseaseSusceptibility;
  final String difficulty;
  final String seasonalCare;

  PlantMaintenance({
    required this.pruning,
    required this.pestSusceptibility,
    required this.diseaseSusceptibility,
    required this.difficulty,
    required this.seasonalCare,
  });

  factory PlantMaintenance.fromJson(Map<String, dynamic> j) => PlantMaintenance(
        pruning: j['pruning'] ?? '',
        pestSusceptibility: j['pest_susceptibility'] ?? '',
        diseaseSusceptibility: j['disease_susceptibility'] ?? '',
        difficulty: j['difficulty'] ?? '',
        seasonalCare: j['seasonal_care'] ?? '',
      );
}

class PlantVariety {
  final String name;
  final String difficulty;
  final String note;

  PlantVariety({required this.name, required this.difficulty, required this.note});

  factory PlantVariety.fromJson(Map<String, dynamic> j) => PlantVariety(
        name: j['name'] ?? '',
        difficulty: j['difficulty'] ?? '',
        note: j['note'] ?? '',
      );
}

class SimilarPlant {
  final String name;
  final String scientificName;
  final String reason;
  final List<String> tags;
  final int score; // 0-100 similarity score
  final String category;
  final String imageQuery; // normalized name for image lookup (strips parentheticals)

  SimilarPlant({
    required this.name,
    required this.scientificName,
    this.reason = '',
    this.tags = const [],
    this.score = 0,
    this.category = '',
    this.imageQuery = '',
  });

  factory SimilarPlant.fromJson(dynamic j) {
    if (j is String) return SimilarPlant(name: j, scientificName: '');
    final m = j as Map<String, dynamic>;
    return SimilarPlant(
      name: m['name'] as String? ?? '',
      scientificName: m['scientific_name'] as String? ?? '',
      reason: m['reason'] as String? ?? '',
      tags: List<String>.from(m['tags'] as List? ?? []),
      score: (m['score'] as num?)?.toInt() ?? 0,
      category: m['category'] as String? ?? '',
      imageQuery: m['image_query'] as String? ?? '',
    );
  }
}

class PlantFlowering {
  final String flowerColor;
  final List<String> flowerColors;
  final String floweringSeason;
  final String fruitingSeason;
  final String harvestInfo;
  final List<PlantVariety> popularVarieties;
  final List<String> popularInRegion;
  final String priceSmall;
  final String priceMedium;
  final String priceLarge;
  final List<SimilarPlant> similarPlants;
  final List<SimilarPlant> similarFlowers;
  final List<SimilarPlant> malaysiaAlternatives;

  PlantFlowering({
    required this.flowerColor,
    required this.flowerColors,
    required this.floweringSeason,
    required this.fruitingSeason,
    required this.harvestInfo,
    required this.popularVarieties,
    required this.popularInRegion,
    required this.priceSmall,
    required this.priceMedium,
    required this.priceLarge,
    required this.similarPlants,
    this.similarFlowers = const [],
    this.malaysiaAlternatives = const [],
  });

  factory PlantFlowering.fromJson(Map<String, dynamic> j) => PlantFlowering(
        flowerColor: j['flower_color'] ?? '',
        flowerColors: List<String>.from(j['flower_colors'] ?? []),
        floweringSeason: j['flowering_season'] ?? '',
        fruitingSeason: j['fruiting_season'] ?? '',
        harvestInfo: j['harvest_info'] ?? '',
        popularVarieties: (j['popular_varieties'] as List? ?? [])
            .map((v) => PlantVariety.fromJson(v as Map<String, dynamic>))
            .toList(),
        popularInRegion: List<String>.from(j['popular_in_region'] ?? []),
        priceSmall: j['price_small'] ?? '',
        priceMedium: j['price_medium'] ?? '',
        priceLarge: j['price_large'] ?? '',
        similarPlants: (j['similar_plants'] as List? ?? []).map(SimilarPlant.fromJson).toList(),
        similarFlowers: (j['similar_flowers'] as List? ?? []).map(SimilarPlant.fromJson).toList(),
        malaysiaAlternatives: (j['malaysia_alternatives'] as List? ?? []).map(SimilarPlant.fromJson).toList(),
      );
}

class PlantPurchaseDecision {
  final List<String> advantages;
  final List<String> challenges;
  final int suitabilityScore;
  final String recommendation;
  final String summary;

  PlantPurchaseDecision({
    required this.advantages,
    required this.challenges,
    required this.suitabilityScore,
    required this.recommendation,
    required this.summary,
  });

  factory PlantPurchaseDecision.fromJson(Map<String, dynamic> j) => PlantPurchaseDecision(
        advantages: List<String>.from(j['advantages'] ?? []),
        challenges: List<String>.from(j['challenges'] ?? []),
        suitabilityScore: (j['suitability_score'] ?? 0) is int
            ? j['suitability_score'] ?? 0
            : int.tryParse(j['suitability_score'].toString()) ?? 0,
        recommendation: j['recommendation'] ?? '',
        summary: j['summary'] ?? '',
      );
}

// ── Special Plant (botanical / conservation) educational data ─────────────────
class SpecialPlantInfo {
  final bool isLargestFlower;
  final String flowerDiameter;
  final String flowerLifespan;
  final String nativeRegion;
  final String conservationStatus;
  final String hostPlant;
  final bool hostPlantRequired;
  final String habitat;
  final String cultivationNote;
  final List<String> interestingFacts;

  const SpecialPlantInfo({
    this.isLargestFlower = false,
    this.flowerDiameter = '',
    this.flowerLifespan = '',
    this.nativeRegion = '',
    this.conservationStatus = '',
    this.hostPlant = '',
    this.hostPlantRequired = false,
    this.habitat = '',
    this.cultivationNote = '',
    this.interestingFacts = const [],
  });

  factory SpecialPlantInfo.fromJson(Map<String, dynamic> j) => SpecialPlantInfo(
    isLargestFlower:    j['is_largest_flower']    as bool?   ?? false,
    flowerDiameter:     j['flower_diameter']       as String? ?? '',
    flowerLifespan:     j['flower_lifespan']       as String? ?? '',
    nativeRegion:       j['native_region']         as String? ?? '',
    conservationStatus: j['conservation_status']   as String? ?? '',
    hostPlant:          j['host_plant']            as String? ?? '',
    hostPlantRequired:  j['host_plant_required']   as bool?   ?? false,
    habitat:            j['habitat']               as String? ?? '',
    cultivationNote:    j['cultivation_note']      as String? ?? '',
    interestingFacts:   (j['interesting_facts'] as List<dynamic>?)
                            ?.map((e) => e.toString())
                            .toList() ?? const [],
  );
}

class NurseryPrice {
  final String small;
  final String medium;
  final String large;
  final String confidence;
  final String unavailableMessage; // non-empty for botanical_only plants

  const NurseryPrice({
    required this.small,
    required this.medium,
    required this.large,
    required this.confidence,
    this.unavailableMessage = '',
  });

  static const unavailable = NurseryPrice(small: '', medium: '', large: '', confidence: '');

  bool get hasData => small.isNotEmpty || medium.isNotEmpty || large.isNotEmpty || unavailableMessage.isNotEmpty;

  bool get isNotCommerciallyAvailable => unavailableMessage.isNotEmpty;

  factory NurseryPrice.fromJson(Map<String, dynamic> j) => NurseryPrice(
        small:              j['small']               as String? ?? '',
        medium:             j['medium']              as String? ?? '',
        large:              j['large']               as String? ?? '',
        confidence:         j['confidence']          as String? ?? 'Estimated',
        unavailableMessage: j['unavailable_message'] as String? ?? '',
      );
}

class PlantHealth {
  final String healthStatus;
  final String disease;
  final bool petSafe;           // backward compat (compare/report screens)
  final String toxicityNotes;
  // Enhanced pet safety fields (populated by pet_safety_service)
  final String petSafetyStatus;   // safe | caution | toxic | unknown
  final String petSafetySource;   // VERIFIED_DATABASE | AI_RESEARCH | database | ai | unknown
  final String affectedAnimals;
  final String symptoms;
  final String toxicityLevel;     // None | Mild | Moderate | High
  final int petSafetyConfidence;  // 0–100 (100 = verified DB, 70–99 = AI Research)

  PlantHealth({
    required this.healthStatus,
    required this.disease,
    required this.petSafe,
    required this.toxicityNotes,
    this.petSafetyStatus = 'unknown',
    this.petSafetySource = 'unknown',
    this.affectedAnimals = '',
    this.symptoms = '',
    this.toxicityLevel = '',
    this.petSafetyConfidence = 0,
  });

  factory PlantHealth.fromJson(Map<String, dynamic> j) => PlantHealth(
        healthStatus:   j['health_status'] ?? 'Unknown',
        disease:        j['disease'] ?? 'None',
        petSafe:        j['pet_safe'] == true || j['pet_safe'].toString() == 'true',
        toxicityNotes:  j['toxicity_notes'] ?? '',
        petSafetyStatus: j['pet_safety_status'] as String? ?? 'unknown',
        petSafetySource: j['pet_safety_source'] as String? ?? 'unknown',
        affectedAnimals: j['affected_animals'] as String? ?? '',
        symptoms:        j['symptoms'] as String? ?? '',
        toxicityLevel:   j['toxicity_level'] as String? ?? '',
        petSafetyConfidence: (j['pet_safety_confidence'] as num?)?.toInt() ?? 0,
      );
}

class Plant {
  final PlantIdentification identification;
  final PlantSuitability suitability;
  final PlantGrowing growing;
  final PlantSpace space;
  final PlantMaintenance maintenance;
  final PlantFlowering flowering;
  final PlantPurchaseDecision purchaseDecision;
  final PlantHealth health;
  final NurseryPrice nurseryPrice;
  /// 'common_garden' | 'specialty_garden' | 'advanced_collector' | 'botanical_only'
  final String cultivationCategory;
  /// 0-100 holistic home-garden suitability score (0 = impossible; 100 = perfect)
  final int gardenabilityScore;
  /// Human-readable score band — canonical label from the backend score_band object.
  /// e.g. "Excellent for Malaysian Gardens", "Recommended", "Challenging", etc.
  final String scoreBandLabel;
  /// Short version of the band label for compact UI contexts.
  final String scoreBandShort;
  /// True for legally protected, parasitic, or institutionally-only plants
  final bool isSpecialPlant;
  /// Botanical / educational facts — only present for special plants
  final SpecialPlantInfo? specialPlantInfo;

  Plant({
    required this.identification,
    required this.suitability,
    required this.growing,
    required this.space,
    required this.maintenance,
    required this.flowering,
    required this.purchaseDecision,
    required this.health,
    this.nurseryPrice = NurseryPrice.unavailable,
    this.cultivationCategory = 'common_garden',
    this.gardenabilityScore = 75,
    this.scoreBandLabel = 'Recommended',
    this.scoreBandShort = 'Recommended',
    this.isSpecialPlant = false,
    this.specialPlantInfo,
  });

  factory Plant.fromJson(Map<String, dynamic> json) {
    final bandMap = json['score_band'] as Map<String, dynamic>?;
    final score   = (json['gardenability_score'] as num?)?.toInt() ?? 75;
    return Plant(
      identification:      PlantIdentification.fromJson(json['identification'] ?? {}),
      suitability:         PlantSuitability.fromJson(json['suitability'] ?? {}),
      growing:             PlantGrowing.fromJson(json['growing'] ?? {}),
      space:               PlantSpace.fromJson(json['space'] ?? {}),
      maintenance:         PlantMaintenance.fromJson(json['maintenance'] ?? {}),
      flowering:           PlantFlowering.fromJson(json['flowering'] ?? {}),
      purchaseDecision:    PlantPurchaseDecision.fromJson(json['purchase_decision'] ?? {}),
      health:              PlantHealth.fromJson(json['health'] ?? {}),
      nurseryPrice: json['nursery_price'] != null
          ? NurseryPrice.fromJson(json['nursery_price'] as Map<String, dynamic>)
          : NurseryPrice.unavailable,
      cultivationCategory: json['cultivation_category'] as String? ?? 'common_garden',
      gardenabilityScore:  score,
      scoreBandLabel: bandMap?['label'] as String? ?? _fallbackBandLabel(score),
      scoreBandShort: bandMap?['short_label'] as String? ?? _fallbackBandLabel(score),
      isSpecialPlant:      json['special_plant'] as bool? ?? false,
      specialPlantInfo: json['botanical_info'] != null
          ? SpecialPlantInfo.fromJson(json['botanical_info'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Client-side fallback in case the backend response predates score_band.
  static String _fallbackBandLabel(int score) {
    if (score >= 81) return 'Highly Recommended';
    if (score >= 61) return 'Recommended';
    if (score >= 41) return 'Moderate';
    if (score >= 21) return 'Challenging';
    if (score >= 10) return 'Not Recommended';
    return 'Botanical Only';
  }
}
