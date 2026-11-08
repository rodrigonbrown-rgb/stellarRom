.class final Landroid/hardware/face/CrewFaceFacade$PreEnroll;
.super Lcom/samsung/android/bio/face/SemBioFaceManager$ChallengeCallback;
.source "CrewFaceFacade.java"


# crew: legacy challenge (onPreEnroll) -> FaceManager.GenerateChallengeCallback
.field final cb:Landroid/hardware/face/FaceManager$GenerateChallengeCallback;

.field final user:I


.method constructor <init>(Landroid/hardware/face/FaceManager$GenerateChallengeCallback;I)V
    .locals 0

    invoke-direct {p0}, Lcom/samsung/android/bio/face/SemBioFaceManager$ChallengeCallback;-><init>()V

    iput-object p1, p0, Landroid/hardware/face/CrewFaceFacade$PreEnroll;->cb:Landroid/hardware/face/FaceManager$GenerateChallengeCallback;

    iput p2, p0, Landroid/hardware/face/CrewFaceFacade$PreEnroll;->user:I

    return-void
.end method

.method public onPreEnroll(J)V
    .locals 5

    iget-object v0, p0, Landroid/hardware/face/CrewFaceFacade$PreEnroll;->cb:Landroid/hardware/face/FaceManager$GenerateChallengeCallback;

    if-eqz v0, :cond_0

    const/4 v1, 0x0

    iget v2, p0, Landroid/hardware/face/CrewFaceFacade$PreEnroll;->user:I

    move-wide v3, p1

    invoke-interface {v0, v1, v2, v3, v4}, Landroid/hardware/face/FaceManager$GenerateChallengeCallback;->onGenerateChallengeResult(IIJ)V

    :cond_0
    return-void
.end method
