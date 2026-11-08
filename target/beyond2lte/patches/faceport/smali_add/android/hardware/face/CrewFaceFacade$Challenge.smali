.class final Landroid/hardware/face/CrewFaceFacade$Challenge;
.super Ljava/lang/Object;
.source "CrewFaceFacade.java"

# interfaces
.implements Ljava/lang/Runnable;

.field final cb:Landroid/hardware/face/FaceManager$GenerateChallengeCallback;

.field final challenge:J

.field final user:I


.method constructor <init>(Landroid/hardware/face/FaceManager$GenerateChallengeCallback;IJ)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Landroid/hardware/face/CrewFaceFacade$Challenge;->cb:Landroid/hardware/face/FaceManager$GenerateChallengeCallback;

    iput p2, p0, Landroid/hardware/face/CrewFaceFacade$Challenge;->user:I

    iput-wide p3, p0, Landroid/hardware/face/CrewFaceFacade$Challenge;->challenge:J

    return-void
.end method

.method public run()V
    .locals 5

    iget-object v0, p0, Landroid/hardware/face/CrewFaceFacade$Challenge;->cb:Landroid/hardware/face/FaceManager$GenerateChallengeCallback;

    if-eqz v0, :cond_0

    const/4 v1, 0x0

    iget v2, p0, Landroid/hardware/face/CrewFaceFacade$Challenge;->user:I

    iget-wide v3, p0, Landroid/hardware/face/CrewFaceFacade$Challenge;->challenge:J

    invoke-interface {v0, v1, v2, v3, v4}, Landroid/hardware/face/FaceManager$GenerateChallengeCallback;->onGenerateChallengeResult(IIJ)V

    :cond_0
    return-void
.end method
