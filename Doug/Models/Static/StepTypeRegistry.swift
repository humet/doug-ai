import Foundation

enum StepTypeRegistry {
    private static let types: [StepTypeID: StepType] = [
        .buildLevain: StepType(
            id: .buildLevain,
            label: "Build Levain",
            classification: .passiveFixed,
            baseDurationMinutes: 300,
            isTemperatureAdjusted: true,
            referenceTemperatureCelsius: 24.0,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Mix starter with flour and water at the specified ratio. Cover and leave at room temperature until doubled and domed.",
            notificationText: "Time to build your levain — mix starter, flour, and water. It'll need a few hours to peak."
        ),

        .autolyse: StepType(
            id: .autolyse,
            label: "Autolyse",
            classification: .passiveFlexible,
            baseDurationMinutes: 45,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: 30...60,
            requiresTempReading: false,
            instructionText: "Mix flour and water until no dry flour remains. Cover and rest. Do not add salt or levain yet.",
            notificationText: "Time to autolyse — mix flour and water, then rest. No salt or levain yet."
        ),

        .mix: StepType(
            id: .mix,
            label: "Mix",
            classification: .handsOn,
            baseDurationMinutes: 5,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: true,
            instructionText: "Add levain and salt to the autolysed dough. Pinch and fold until fully incorporated. Take a dough temperature reading.",
            notificationText: "Time to mix — add levain and salt, pinch and fold until incorporated. Take a dough temp reading."
        ),

        .bulkFerment: StepType(
            id: .bulkFerment,
            label: "Bulk Ferment",
            classification: .passiveFixed,
            baseDurationMinutes: 240,
            isTemperatureAdjusted: true,
            referenceTemperatureCelsius: 24.0,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Let the dough ferment at room temperature. Perform stretch and folds at intervals during the first portion.",
            notificationText: "Bulk ferment is underway — stretch and folds are scheduled within this window."
        ),

        .stretchAndFold: StepType(
            id: .stretchAndFold,
            label: "Stretch & Fold",
            classification: .handsOn,
            baseDurationMinutes: 3,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: true,
            instructionText: "Wet your hands. Stretch one side of the dough up and fold it over. Rotate 90° and repeat 3 more times. Take a dough temp reading.",
            notificationText: "Time for a stretch & fold — wet hands, stretch and fold four sides. Log your dough temperature."
        ),

        .addInclusions: StepType(
            id: .addInclusions,
            label: "Add Inclusions",
            classification: .handsOn,
            baseDurationMinutes: 2,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Spread the dough out gently and distribute inclusions evenly. Fold the dough over to enclose them, then perform a stretch and fold.",
            notificationText: "Time to add inclusions — spread dough, distribute evenly, fold to enclose."
        ),

        .shape: StepType(
            id: .shape,
            label: "Shape",
            classification: .handsOn,
            baseDurationMinutes: 20,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Pre-shape into a round. Rest 15 minutes. Final shape into a tight ball or batard. Place seam-side up in a floured banneton.",
            notificationText: "Time to shape — pre-shape, bench rest 15 min, then final shape into banneton."
        ),

        .coldRetard: StepType(
            id: .coldRetard,
            label: "Cold Retard",
            classification: .passiveFlexible,
            baseDurationMinutes: 720,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: 480...1080,
            requiresTempReading: false,
            instructionText: "Cover the banneton and place in the fridge. The dough will slowly ferment and develop flavour. Longer retards give more sour flavour.",
            notificationText: "Into the fridge — your dough will cold retard. You can adjust the duration if life gets in the way."
        ),

        .preheat: StepType(
            id: .preheat,
            label: "Preheat",
            classification: .passiveFixed,
            baseDurationMinutes: 60,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Place your dutch oven (lid on) in the oven and preheat to the recipe's bake temperature. Allow a full hour for the pot to heat through.",
            notificationText: "Time to preheat — get the dutch oven in and set your oven temperature. Full hour to heat through."
        ),

        .bakeCovered: StepType(
            id: .bakeCovered,
            label: "Bake (Covered)",
            classification: .passiveFixed,
            baseDurationMinutes: 20,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Score the dough and carefully load it into the hot dutch oven. Cover with the lid and bake.",
            notificationText: "Time to bake — score your dough, load into the hot dutch oven, and bake with the lid on."
        ),

        .bakeUncovered: StepType(
            id: .bakeUncovered,
            label: "Bake (Uncovered)",
            classification: .passiveFixed,
            baseDurationMinutes: 25,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Remove the lid and continue baking until the crust is deep golden brown. The internal temperature should reach 96–98°C.",
            notificationText: "Remove the lid — bake uncovered until deep golden brown. Your bread is almost ready!"
        ),
    ]

    static func type(for id: StepTypeID) -> StepType {
        guard let stepType = types[id] else {
            fatalError("Missing StepType definition for \(id.rawValue)")
        }
        return stepType
    }
}
