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
            notificationText: "Time to build your levain — mix starter, flour, and water. It'll need a few hours to peak.",
            successSignal: "Levain has at least doubled, with a domed top and bubbly surface. A spoonful dropped in water should float."
        ),

        .autolyse: StepType(
            id: .autolyse,
            label: "Autolyse",
            classification: .passiveFlexible,
            baseDurationMinutes: 45,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: 30 ... 60,
            requiresTempReading: false,
            instructionText: "Mix flour and water until no dry flour remains. Cover and rest. Do not add salt or levain yet.",
            notificationText: "Time to autolyse — mix flour and water, then rest. No salt or levain yet.",
            successSignal: "Dough has relaxed into a shaggy, hydrated mass with no dry flour visible.",
            staleness: StalenessInfo(
                thresholdMinutes: 120,
                warning: "Your levain has been sitting well past its peak. It'll be weaker and more acidic — expect a denser, more sour loaf with less oven spring.",
                salvageAdvice: "Pop the levain in the fridge and feed it tomorrow. Your flour is untouched — nothing wasted."
            )
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
            notificationText: "Time to mix — add levain and salt, pinch and fold until incorporated. Take a dough temp reading.",
            successSignal: "Dough is smooth, even, and cohesive — no streaks of unmixed levain or salt remain.",
            staleness: StalenessInfo(
                thresholdMinutes: 180,
                warning: "Your autolyse has been sitting a long time. Protease enzymes are breaking down the gluten network — the dough will feel slacker than normal, especially with whole grain flour.",
                salvageAdvice: "Continue — the dough is still usable. Handle gently during shaping and expect a slightly more open, less structured crumb."
            )
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
            notificationText: "Bulk ferment is underway — stretch and folds are scheduled within this window.",
            successSignal: "Dough has risen 50–75%, feels airy, and shows bubbles on the surface and sides of the container.",
            staleness: StalenessInfo(
                thresholdMinutes: 60,
                warning: "Your dough has been fermenting since you mixed it — the timer doesn't account for the time that's already passed. A full bulk on top of this extra time risks over-fermenting.",
                salvageAdvice: "Start the timer, but watch the dough rather than the clock. If it's already risen 50%+ and looks bubbly, consider shaping early."
            )
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
            notificationText: "Time for a stretch & fold — wet hands, stretch and fold four sides. Log your dough temperature.",
            successSignal: "Dough resists the stretch more than last time and holds a neater package shape.",
            staleness: StalenessInfo(
                thresholdMinutes: 45,
                warning: "Missing a fold won't ruin the bread, but the dough may be less structured. Skip it and let bulk continue — don't try to fold a dough that's already fermented past this point.",
                salvageAdvice: "Skip this fold and carry on. If you've missed several folds, expect a flatter, more open crumb."
            )
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
            notificationText: "Time to add inclusions — spread dough, distribute evenly, fold to enclose.",
            successSignal: "Inclusions are evenly distributed through the dough, not clustered in pockets.",
            staleness: StalenessInfo(
                thresholdMinutes: 30,
                warning: "The dough has fermented further since this step was due. Adding inclusions now means more handling on a gassier dough — you'll lose some rise.",
                salvageAdvice: "You can still add them — be gentle. Or skip inclusions entirely and bake a plain loaf."
            )
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
            notificationText: "Time to shape — pre-shape, bench rest 15 min, then final shape into banneton.",
            successSignal: "Dough holds a taut surface and bounces back slowly when poked — not slack, not over-tight.",
            staleness: StalenessInfo(
                thresholdMinutes: 60,
                warning: "The dough has been bulk fermenting longer than planned. It may be over-proofed — expect it to be loose, sticky, and hard to shape, with a flat, dense result.",
                salvageAdvice: "If the dough is still holding some structure, shape it gently and go straight to the fridge. If it's a puddle, use it for focaccia or flatbread — press it into an oiled tray, dimple, top, and bake at 220\u{00B0}C for 20 minutes."
            )
        ),

        .coldRetard: StepType(
            id: .coldRetard,
            label: "Cold Retard",
            classification: .passiveFlexible,
            baseDurationMinutes: 720,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: 480 ... 1080,
            requiresTempReading: false,
            instructionText: "Cover the banneton and place in the fridge. The dough will slowly ferment and develop flavour. Longer retards give more sour flavour.",
            notificationText: "Into the fridge — your dough will cold retard. You can adjust the duration if life gets in the way.",
            successSignal: "Dough feels firm and cold to the touch, with a slightly tacky surface — ready to score straight from the fridge.",
            staleness: StalenessInfo(
                thresholdMinutes: 45,
                warning: "Your shaped dough has been sitting at room temperature. It's proofing fast — the longer it waits, the more likely it over-proofs and loses oven spring.",
                salvageAdvice: "Get it in the fridge immediately if it still has some tension. If it's very puffy and jiggly, it's over-proofed — bake it straight away instead of retarding, or use it as flatbread dough."
            )
        ),

        .finalProof: StepType(
            id: .finalProof,
            label: "Final Proof",
            classification: .passiveFlexible,
            baseDurationMinutes: 90,
            isTemperatureAdjusted: true,
            referenceTemperatureCelsius: 24.0,
            flexRange: 60 ... 180,
            requiresTempReading: false,
            instructionText: "Cover the shaped dough and leave at room temperature. It will puff up gradually — use the poke test to judge readiness.",
            notificationText: "Your dough is proofing at room temperature. Keep an eye on it — over-proofing is the main risk.",
            successSignal: "Dough springs back slowly when poked with a floured finger, leaving a slight indent. If it springs back fast, it needs more time.",
            staleness: StalenessInfo(
                thresholdMinutes: 30,
                warning: "Your dough has been proofing at room temperature longer than planned. It may be over-proofed — puffy, jiggly, and lacking tension.",
                salvageAdvice: "If it still holds some shape, bake it now — don't wait. If it's completely slack, press it into an oiled tray and bake as focaccia."
            )
        ),

        .panShape: StepType(
            id: .panShape,
            label: "Pan Shape",
            classification: .handsOn,
            baseDurationMinutes: 10,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Generously oil a sheet pan or baking tray. Turn the dough out onto it and gently stretch to fill the pan. Dimple the surface with your fingertips and drizzle with olive oil.",
            notificationText: "Time to pan-shape — oil the tray, stretch the dough in, dimple, and drizzle.",
            successSignal: "Dough fills most of the pan evenly, with a dimpled surface glistening with olive oil."
        ),

        .bakeSheet: StepType(
            id: .bakeSheet,
            label: "Bake",
            classification: .passiveFixed,
            baseDurationMinutes: 25,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            requiresPresence: true,
            instructionText: "Place the pan in the preheated oven and bake until golden on top and crisp underneath.",
            notificationText: "Time to bake — get the pan in the oven.",
            successSignal: "Top is golden brown and crisp, bottom sounds hollow when tapped, and the edges have pulled away from the pan slightly.",
            staleness: StalenessInfo(
                thresholdMinutes: 30,
                warning: "Your oven has been at temperature for a long time — wasting energy, but the dough on the counter is still fine.",
                salvageAdvice: "Turn the oven off and try again when you're ready."
            )
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
            requiresPresence: true,
            instructionText: "Place your dutch oven (lid on) in the oven and preheat to the recipe's bake temperature. Allow a full hour for the pot to heat through.",
            notificationText: "Time to preheat — get the dutch oven in and set your oven temperature. Full hour to heat through.",
            successSignal: "Oven has held target temperature for at least 15 minutes and the dutch oven is thoroughly hot."
        ),

        .bake: StepType(
            id: .bake,
            label: "Bake",
            classification: .passiveFixed,
            baseDurationMinutes: 45,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            requiresPresence: true,
            instructionText: "Score the dough and load it into the hot dutch oven. Bake covered first for oven spring, then remove the lid to develop the crust.",
            notificationText: "Time to bake — score your dough and load into the hot dutch oven.",
            successSignal: "Crust is deep mahogany, the loaf sounds hollow when tapped underneath, and internal temperature reads 96–98°C.",
            staleness: StalenessInfo(
                thresholdMinutes: 30,
                warning: "Your oven has been at temperature for a long time — wasting energy, but the dough in the fridge is fine. No harm to the bread.",
                salvageAdvice: "Turn the oven off and try again when you're ready. The dough will keep in the fridge."
            )
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
            requiresPresence: true,
            instructionText: "Score the dough and carefully load it into the hot dutch oven. Cover with the lid and bake.",
            notificationText: "Time to bake — score your dough, load into the hot dutch oven, and bake with the lid on.",
            successSignal: "Loaf has sprung up tall and the score has opened into an ear — crust is pale but set.",
            staleness: StalenessInfo(
                thresholdMinutes: 30,
                warning: "Your oven has been at temperature for a long time — wasting energy, but the dough in the fridge is fine. No harm to the bread.",
                salvageAdvice: "Turn the oven off and try again when you're ready. The dough will keep in the fridge."
            )
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
            requiresPresence: true,
            instructionText: "Remove the lid and continue baking until the crust is deep golden brown. The internal temperature should reach 96–98°C.",
            notificationText: "Remove the lid — bake uncovered until deep golden brown. Your bread is almost ready!",
            successSignal: "Crust is deep mahogany, the loaf sounds hollow when tapped underneath, and internal temperature reads 96–98°C.",
            staleness: StalenessInfo(
                thresholdMinutes: 10,
                warning: "Your bread has been baking covered too long. The extra steam keeps the crust pale and chewy instead of crisp — and the loaf may be slightly over-baked inside.",
                salvageAdvice: "Remove the lid now. The crust will be pale — give it a full 20–25 minutes uncovered to develop colour. Check it's not burning towards the end."
            )
        ),

        .fridgeRest: StepType(
            id: .fridgeRest,
            label: "Starter Resting",
            classification: .passiveFixed,
            baseDurationMinutes: 0,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Your starter is resting in the fridge. We'll notify you when it's time to take it out and feed it.",
            notificationText: "Your starter is resting — nothing to do yet.",
            successSignal: "Time to activate your starter."
        ),

        .activateStarter: StepType(
            id: .activateStarter,
            label: "Activate Starter",
            classification: .handsOn,
            baseDurationMinutes: 10,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Take your starter out of the fridge and feed it at your usual activation ratio. Place it somewhere warm and covered.",
            notificationText: "Time to activate your starter — take it out of the fridge and feed it.",
            successSignal: "Starter is fed and on the counter. Now wait for it to peak."
        ),

        .waitForPeak: StepType(
            id: .waitForPeak,
            label: "Wait for Peak",
            classification: .passiveFixed,
            baseDurationMinutes: 300,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Your starter is rising. Wait for it to at least double in size with a domed top. Mark the peak when it's ready.",
            notificationText: "Your starter should be close to peaking — check if it has doubled.",
            successSignal: "Starter has peaked — doubled in size with a domed, bubbly surface."
        ),

        .refeedAndRefrigerate: StepType(
            id: .refeedAndRefrigerate,
            label: "Feed & Refrigerate Starter",
            classification: .handsOn,
            baseDurationMinutes: 10,
            isTemperatureAdjusted: false,
            referenceTemperatureCelsius: nil,
            flexRange: nil,
            requiresTempReading: false,
            instructionText: "Feed your leftover starter at 1:1:1 and return it to the fridge. It will rest until your next bake.",
            notificationText: "Don't forget to feed your starter and put it back in the fridge!",
            successSignal: "Starter is fed and back in the fridge."
        ),
    ]

    static func type(for id: StepTypeID) -> StepType {
        guard let stepType = types[id] else {
            fatalError("Missing StepType definition for \(id.rawValue)")
        }
        return stepType
    }
}
